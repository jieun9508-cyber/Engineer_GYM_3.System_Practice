# -----------------------------
# graph_review_spof_bottleneck_v2.py
# 목적:
# 1) DB에서 가장 최근 submission의 mermaid_text를 가져옴
# 2) Mermaid 텍스트를 "노드/엣지(그래프)" 구조로 파싱
# 3) SPOF 후보(단절점) / 병목 후보(중앙성+fan-in) 계산
# 4) system_results.score_breakdown_json에 graph_analysis 추가
# 5) SPOF/병목에 따라 score_total 감점 반영 + risk_flags 추가
# 전제:
# - 03_demo_submission_result.sql로 system_results row가 이미 생성돼 있어야 함
# -----------------------------

import re
import json
from typing import Dict, List, Tuple, Set, Optional

import mysql.connector
import networkx as nx


# -----------------------------
# [A] 감점 정책(원하시면 여기만 조정)
# -----------------------------
SPOF_PENALTY_PER = 12          # SPOF 후보 1개당 감점
SPOF_PENALTY_CAP = 36          # SPOF 감점 최대치
BOTTLENECK_PENALTY_PER = 6     # 병목 후보 1개당 감점
BOTTLENECK_PENALTY_CAP = 18    # 병목 감점 최대치


# -----------------------------
# [B] Mermaid 파싱용 정규식(Flowchart MVP 버전)
# -----------------------------
# 노드 라벨 정의: A[Label], A(Label), A{Label}
LABEL_DEF_RE = re.compile(r"([A-Za-z0-9_]+)\s*(\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\})")

# 라인 단위 엣지: A --> B, A -->|text| B 형태를 우선 지원
EDGE_LINE_RE = re.compile(
    r"^\s*([A-Za-z0-9_]+)(?:\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\})?\s*[-.]*>\s*(?:\|[^|]*\|\s*)?([A-Za-z0-9_]+)"
)

# 체인 파싱 시 노드 ID를 뽑기 위한 매우 단순한 패턴
NODE_ID_RE = re.compile(r"\b([A-Za-z0-9_]+)\b")

# Mermaid 주석 라인(%%로 시작)
COMMENT_LINE_RE = re.compile(r"^\s*%%")


# -----------------------------
# [C] Mermaid 주석 힌트 파싱
# -----------------------------
def parse_annotations(mermaid_text: str) -> Tuple[Set[str], Optional[str], Optional[str]]:
    """
    Mermaid 주석(%%)에 아래 힌트를 적어두면 정확도가 좋아집니다.
    - %% redundant: G,R  => G, R은 이중화로 간주하여 SPOF 후보에서 제외
    - %% entry: U        => entry 노드 지정(시작점)
    - %% exit: V         => exit 노드 지정(종착점)
    """
    redundant: Set[str] = set()
    entry = None
    exit_ = None

    for raw in mermaid_text.splitlines():
        line = raw.strip()
        if not line.startswith("%%"):
            continue

        low = line.lower()

        if "redundant:" in low:
            part = line.split("redundant:", 1)[1]
            redundant |= {x.strip() for x in part.split(",") if x.strip()}

        if "entry:" in low:
            entry = line.split("entry:", 1)[1].strip()

        if "exit:" in low:
            exit_ = line.split("exit:", 1)[1].strip()

    return redundant, entry, exit_


# -----------------------------
# [D] Mermaid 라인 정리
# -----------------------------
def normalize_line(line: str) -> str:
    """
    - 엣지 라벨 |text| 제거 (A -->|label| B)
    - 앞뒤 공백 제거
    """
    line = re.sub(r"\|[^|]*\|", "", line)  # |...| 제거
    return line.strip()


# -----------------------------
# [E] Mermaid -> (edges, labels) 파싱
# -----------------------------
def parse_mermaid_edges_and_labels(mermaid_text: str) -> Tuple[List[Tuple[str, str]], Dict[str, str]]:
    """
    반환:
    - edges: [(A,B), (B,C), ...]  (방향 그래프)
    - labels: {A:"User", B:"Gateway", ...}
    """
    labels: Dict[str, str] = {}
    edges: List[Tuple[str, str]] = []

    # (1) 라벨 정의 수집: A[Gateway] 형태
    for m in LABEL_DEF_RE.finditer(mermaid_text):
        node_id = m.group(1)
        raw_label = m.group(2).strip("[](){}")
        labels[node_id] = raw_label

    # (2) 엣지 수집
    for raw in mermaid_text.splitlines():
        if COMMENT_LINE_RE.match(raw):  # %% 주석라인은 엣지로 보지 않음
            continue

        line = raw.strip()
        if not line:
            continue

        low = line.lower()

        # Mermaid 선언/서브그래프 키워드는 MVP에서 무시
        if low.startswith("graph ") or low.startswith("flowchart "):
            continue
        if low.startswith("subgraph") or low == "end":
            continue

        line = normalize_line(line)
        if not line:
            continue

        # 한 줄에 세미콜론으로 여러 문장이 붙는 경우 분리
        parts = [p.strip() for p in line.split(";") if p.strip()]

        for p in parts:
            # (2-a) 가장 기본 케이스: A --> B
            m = EDGE_LINE_RE.match(p)
            if m:
                a, b = m.group(1), m.group(2)
                edges.append((a, b))
                continue

            # (2-b) 체인 케이스: A --> B --> C
            if "-->" in p or "->" in p:
                # 화살표 변형들을 통일해서 split 하기
                tmp = re.sub(r"-{1,3}\.?->", " -> ", p)
                tokens = [t.strip() for t in tmp.split("->") if t.strip()]

                chain_nodes: List[str] = []
                for t in tokens:
                    # 토큰에서 첫 번째 node id만 뽑음(단순 MVP)
                    found = NODE_ID_RE.findall(t)
                    if found:
                        chain_nodes.append(found[0])

                for i in range(len(chain_nodes) - 1):
                    edges.append((chain_nodes[i], chain_nodes[i + 1]))

    # (3) 엣지 중복 제거(순서 유지)
    seen = set()
    uniq_edges: List[Tuple[str, str]] = []
    for e in edges:
        if e not in seen:
            uniq_edges.append(e)
            seen.add(e)

    return uniq_edges, labels


# -----------------------------
# [F] entry/exit 추정
# -----------------------------
def choose_entry_exit(
    G: nx.DiGraph,
    labels: Dict[str, str],
    entry_hint: Optional[str],
    exit_hint: Optional[str]
) -> Tuple[Optional[str], List[str]]:
    """
    entry/exit가 힌트로 주어지면 그대로 사용.
    없으면 휴리스틱:
    - entry: in_degree==0 노드 중 (U/User 라벨 우선), 없으면 첫 후보
    - exit: out_degree==0 노드들 (여러 개일 수 있음)
    """
    entry: Optional[str] = None
    exits: List[str] = []

    # entry 결정
    if entry_hint and entry_hint in G:
        entry = entry_hint
    else:
        candidates = [n for n in G.nodes if G.in_degree(n) == 0]
        for n in candidates:
            lab = (labels.get(n, "") or "").lower()
            if n.lower() in ("u", "user") or "user" in lab:
                entry = n
                break
        if not entry and candidates:
            entry = candidates[0]

    # exit 결정
    if exit_hint and exit_hint in G:
        exits = [exit_hint]
    else:
        exits = [n for n in G.nodes if G.out_degree(n) == 0]

        # out_degree==0가 없으면 라벨 키워드로 추정(최후 수단)
        if not exits:
            key = ["db", "database", "vector", "llm", "model"]
            for n in G.nodes:
                lab = (labels.get(n, "") or "").lower()
                if any(k in lab for k in key):
                    exits.append(n)

    return entry, exits


# -----------------------------
# [G] core 서브그래프(핵심 경로)만 추출
# -----------------------------
def core_subgraph_nodes(G: nx.DiGraph, entry: Optional[str], exits: List[str]) -> Set[str]:
    """
    entry -> exit 로 이어지는 경로에 참여 가능한 노드들만 모아서 core로 삼음.
    노이즈 제거용.
    """
    if not entry or entry not in G or not exits:
        return set(G.nodes)

    reachable_from_entry = nx.descendants(G, entry) | {entry}
    RG = G.reverse(copy=False)

    core: Set[str] = set()
    for ex in exits:
        if ex not in G:
            continue
        can_reach_ex = nx.descendants(RG, ex) | {ex}
        core |= (reachable_from_entry & can_reach_ex)

    return core if core else set(G.nodes)


# -----------------------------
# [H] SPOF 계산(단절점 기반)
# -----------------------------
def compute_spof(
    G: nx.DiGraph,
    entry: Optional[str],
    exits: List[str],
    core_nodes: Set[str],
    redundant: Set[str]
) -> List[str]:
    """
    SPOF 후보:
    - core 서브그래프를 undirected로 보고 articulation points(단절점) 후보를 구함
    - entry/exits/redundant 제외
    - 실제로 entry->exit 경로를 끊는지 검증
    """
    if not entry or entry not in G or not exits:
        return []

    H = G.subgraph(core_nodes).copy()
    UG = H.to_undirected()

    candidates = set(nx.articulation_points(UG))  # 그래프 이론의 단절점 후보
    candidates -= {entry}
    candidates -= set(exits)
    candidates -= set(redundant)

    spofs: List[str] = []
    for node in candidates:
        H2 = H.copy()
        if node not in H2:
            continue
        H2.remove_node(node)

        # exits 중 하나라도 끊기면 SPOF로 간주(보수적으로)
        cut = False
        for ex in exits:
            if ex not in H2:
                cut = True
                break
            if not nx.has_path(H2, entry, ex):
                cut = True
                break

        if cut:
            spofs.append(node)

    return spofs


# -----------------------------
# [I] 병목 후보 계산(중앙성 + fan-in/out)
# -----------------------------
def compute_bottlenecks(
    G: nx.DiGraph,
    core_nodes: Set[str],
    labels: Dict[str, str],
    topk: int = 3
) -> List[Dict]:
    """
    병목 후보:
    - betweenness centrality(중앙성): 경로가 많이 지나가는 노드일수록 큼
    - fan-in: 들어오는 엣지가 많으면 요청이 몰릴 가능성↑
    - stateful(DB/Queue/Redis 등)은 가중치를 조금 부여
    """
    H = G.subgraph(core_nodes).copy()
    if H.number_of_nodes() == 0:
        return []

    bc = nx.betweenness_centrality(H.to_undirected(), normalized=True)

    stateful_keys = ["db", "database", "vector", "redis", "queue", "kafka", "mq", "cache"]
    scored = []

    for n in H.nodes:
        lab = (labels.get(n, "") or "").lower()
        fanin = H.in_degree(n)
        fanout = H.out_degree(n)

        bonus = 0.0
        if any(k in lab for k in stateful_keys):
            bonus += 0.20  # 상태ful 컴포넌트는 병목/리스크 가능성이 높으니 가중

        # 점수: 중앙성 + 팬인/팬아웃 + 보너스
        score = bc.get(n, 0.0) + 0.06 * fanin + 0.02 * fanout + bonus
        scored.append((n, score, fanin, fanout, bc.get(n, 0.0)))

    scored.sort(key=lambda x: x[1], reverse=True)

    results: List[Dict] = []
    for n, score, fanin, fanout, bcv in scored[:topk]:
        results.append({
            "node": n,
            "label": labels.get(n),
            "score": round(score, 4),
            "fanin": fanin,
            "fanout": fanout,
            "betweenness": round(bcv, 4),
        })
    return results


# -----------------------------
# [J] 감점 계산
# -----------------------------
def calc_penalties(spofs: List[str], bottlenecks: List[Dict]) -> Dict:
    """
    SPOF/병목 후보 개수에 따라 감점 계산.
    """
    spof_count = len(spofs)
    bottleneck_count = len(bottlenecks)

    spof_penalty = min(SPOF_PENALTY_CAP, spof_count * SPOF_PENALTY_PER)
    bottleneck_penalty = min(BOTTLENECK_PENALTY_CAP, bottleneck_count * BOTTLENECK_PENALTY_PER)

    total_penalty = spof_penalty + bottleneck_penalty

    return {
        "spof_count": spof_count,
        "bottleneck_count": bottleneck_count,
        "spof_penalty": spof_penalty,
        "bottleneck_penalty": bottleneck_penalty,
        "total_penalty": total_penalty,
        "policy": {
            "spof_per": SPOF_PENALTY_PER,
            "spof_cap": SPOF_PENALTY_CAP,
            "bottleneck_per": BOTTLENECK_PENALTY_PER,
            "bottleneck_cap": BOTTLENECK_PENALTY_CAP,
        }
    }


# -----------------------------
# [K] system_results 업데이트(분석 결과 + 감점 반영)
# -----------------------------
def update_system_results(conn, submission_id: int, graph_analysis: dict, penalty_info: dict):
    """
    - 기존 system_results를 읽어온 뒤
    - score_breakdown_json에 graph_analysis + penalty meta를 합치고
    - score_total을 감점 반영한 값으로 업데이트
    - risk_flags_json에 플래그를 추가
    """
    cur = conn.cursor(dictionary=True)

    # (1) 기존 결과 row 조회
    cur.execute(
        "SELECT score_total, score_breakdown_json, risk_flags_json FROM system_results WHERE submission_id=%s",
        (submission_id,)
    )
    row = cur.fetchone()
    if not row:
        raise RuntimeError("system_results가 없습니다. 먼저 03_demo_submission_result.sql을 실행해 결과 row를 만들어주세요.")

    old_score_total = row["score_total"]

    breakdown = row["score_breakdown_json"]
    flags = row["risk_flags_json"]

    # (2) JSON 문자열이면 파싱해서 dict/list로 바꿈
    if isinstance(breakdown, str):
        breakdown = json.loads(breakdown)
    if isinstance(flags, str):
        flags = json.loads(flags)

    # (3) 감점 적용한 새 점수 계산
    total_penalty = penalty_info["total_penalty"]
    new_score_total = max(0, int(old_score_total) - int(total_penalty))

    # (4) breakdown JSON에 분석 결과를 저장할 자리 확보
    breakdown.setdefault("items", {})
    breakdown.setdefault("meta", {})

    # (5) graph_analysis 저장
    breakdown["items"]["graph_analysis"] = graph_analysis

    # (6) 감점 메타 저장(발표/디버그에 아주 유용)
    breakdown["meta"]["graph_penalty"] = {
        "old_score_total": old_score_total,
        "new_score_total": new_score_total,
        **penalty_info
    }

    # (7) flags 업데이트(중복 제거)
    if not isinstance(flags, list):
        flags = []

    flag_set = set(flags)

    if penalty_info["spof_count"] > 0:
        flag_set.add("SPOF_DETECTED")
        flag_set.add("SCORE_DEDUCTED_FOR_SPOF")

    if penalty_info["bottleneck_count"] > 0:
        flag_set.add("BOTTLENECK_CANDIDATES")
        flag_set.add("SCORE_DEDUCTED_FOR_BOTTLENECKS")

    if total_penalty > 0:
        flag_set.add("GRAPH_PENALTY_APPLIED")

    new_flags = list(flag_set)

    # (8) DB 업데이트 실행
    cur.execute(
        "UPDATE system_results SET score_total=%s, score_breakdown_json=%s, risk_flags_json=%s WHERE submission_id=%s",
        (
            new_score_total,
            json.dumps(breakdown, ensure_ascii=False),
            json.dumps(new_flags, ensure_ascii=False),
            submission_id
        )
    )
    conn.commit()


# -----------------------------
# [L] main: 최근 submission 1건을 분석해서 업데이트
# -----------------------------
def main():
    # ✅ DB 접속 정보는 본인 환경에 맞게 바꾸세요
    conn = mysql.connector.connect(
        host="localhost",
        user="root",
        password="YOUR_PASSWORD",   # <- 여기를 본인 비밀번호로
        database="Engineer_GYM",
    )

    cur = conn.cursor(dictionary=True)

    # (1) 가장 최근 제출 1건 가져오기
    cur.execute("SELECT * FROM system_submissions ORDER BY id DESC LIMIT 1")
    sub = cur.fetchone()
    if not sub:
        print("분석할 submission이 없습니다. 03을 먼저 실행하세요.")
        return

    submission_id = sub["id"]
    mermaid_text = sub["mermaid_text"]

    # (2) Mermaid 주석 힌트 파싱(선택)
    redundant, entry_hint, exit_hint = parse_annotations(mermaid_text)

    # (3) Mermaid -> edges/labels 파싱
    edges, labels = parse_mermaid_edges_and_labels(mermaid_text)

    # (4) 방향 그래프 생성
    G = nx.DiGraph()
    G.add_edges_from(edges)

    # (5) entry/exits 추정
    entry, exits = choose_entry_exit(G, labels, entry_hint, exit_hint)

    # (6) 핵심 경로(core)만 뽑아 노이즈 제거
    core = core_subgraph_nodes(G, entry, exits)

    # (7) SPOF 후보 계산
    spofs = compute_spof(G, entry, exits, core, redundant)

    # (8) 병목 후보 계산(상위 3개)
    bottlenecks = compute_bottlenecks(G, core, labels, topk=3)

    # (9) 감점 계산
    penalty_info = calc_penalties(spofs, bottlenecks)

    # (10) graph_analysis JSON 만들기(결과 저장용)
    graph_analysis = {
        "entry": entry,
        "exits": exits,
        "nodes_cnt": len(G.nodes),
        "edges_cnt": len(G.edges),
        "core_nodes_cnt": len(core),
        "redundant_marked": sorted(list(redundant)),
        "spof_candidates": spofs,
        "bottleneck_candidates": bottlenecks,
        "notes": "MVP: Mermaid를 그래프로 변환하여 단절점(SPOF)/중앙성(병목 후보)을 계산하고 점수 감점에 반영"
    }

    # (11) system_results 업데이트(분석 + 감점 반영)
    update_system_results(conn, submission_id, graph_analysis, penalty_info)

    # (12) 로그 출력(확인용)
    print("[OK] system_results 업데이트 완료")
    print("submission_id =", submission_id)
    print(json.dumps({"graph_analysis": graph_analysis, "penalty_info": penalty_info}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
