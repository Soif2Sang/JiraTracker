#!/usr/bin/env python3
"""Audit the GraphQL point cost of the batched PR summaries query.

Compares the pre-change query (contexts first:50, no isRequired/checkSuite)
with the new one (contexts first:100 + isRequired + checkSuite), for 10 and 50
pull requests, and reports the rate-limit cost returned by GitHub.
"""
import json
import subprocess
import sys

REPO = "dktunited/onepromotion"


def gh(args, data=None):
    cmd = ["gh"] + args
    proc = subprocess.run(cmd, input=data, capture_output=True, text=True)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        raise SystemExit(proc.returncode)
    return json.loads(proc.stdout)


def fetch_refs(limit):
    refs = gh(["pr", "list", "--repo", REPO, "--state", "open", "--limit", str(limit),
               "--json", "number,headRefOid"])
    owner, repo = REPO.split("/")
    return [(owner, repo, r["number"], r["headRefOid"]) for r in refs]


def build_query(refs, variant):
    decls, vars_, frags = [], {}, []
    for i, (owner, repo, number, sha) in enumerate(refs):
        decls += [f"$owner{i}: String!", f"$repo{i}: String!", f"$number{i}: Int!", f"$sha{i}: GitObjectID!"]
        vars_[f"owner{i}"] = owner
        vars_[f"repo{i}"] = repo
        vars_[f"number{i}"] = number
        vars_[f"sha{i}"] = sha

        if variant == "old":
            check_fields = "name status conclusion detailsUrl"
            ctx_first = 50
            extra = ""
        elif variant == "new50":
            check_fields = "name status conclusion detailsUrl isRequired(pullRequestNumber: $number%d) checkSuite { app { slug } }" % i
            ctx_first = 50
            extra = ""
        else:  # new100
            check_fields = "name status conclusion detailsUrl isRequired(pullRequestNumber: $number%d) checkSuite { app { slug } }" % i
            ctx_first = 100
            extra = ""

        frags.append(f"""
        pr{i}: repository(owner: $owner{i}, name: $repo{i}) {{
          pullRequest(number: $number{i}) {{
            reviewThreads(first: 50) {{
              nodes {{ isResolved comments(last: 1) {{ nodes {{ createdAt }} }} }}
              pageInfo {{ hasNextPage }}
            }}
          }}
          object(oid: $sha{i}) {{
            ... on Commit {{
              statusCheckRollup {{
                state
                contexts(first: {ctx_first}) {{
                  nodes {{
                    __typename
                    ... on CheckRun {{ {check_fields} }}
                    ... on StatusContext {{ context state targetUrl }}
                  }}
                }}
              }}
            }}
          }}
        }}
        """)

    query = "query(%s) {\n rateLimit { limit cost remaining nodeCount resetAt }\n%s\n}" % (
        ", ".join(decls), "\n".join(frags))
    return query, vars_


def run(refs, variant, label):
    query, variables = build_query(refs, variant)
    body = json.dumps({"query": query, "variables": variables})
    result = gh(["api", "graphql", "--input", "-"], data=body)
    if "errors" in result:
        print(f"[{label}] ERRORS: {result['errors'][:2]}")
        return
    rl = result["data"]["rateLimit"]
    print(f"[{label:28s}] refs={len(refs):3d} cost={rl['cost']:5} remaining={rl['remaining']:5} "
          f"nodeCount={rl['nodeCount']}")


def run_raw(query, variables, label):
    body = json.dumps({"query": query, "variables": variables})
    result = gh(["api", "graphql", "--input", "-"], data=body)
    if "errors" in result:
        print(f"[{label:28s}] ERRORS: {result['errors'][:2]}")
        return
    rl = result["data"]["rateLimit"]
    print(f"[{label:28s}] cost={rl['cost']:5} remaining={rl['remaining']:5} nodeCount={rl['nodeCount']}")


SEARCH_QUERY = """
query($query: String!) {
  rateLimit { limit cost remaining nodeCount resetAt }
  search(query: $query, type: ISSUE, first: 100) {
    nodes { ... on PullRequest { number title url body updatedAt isDraft mergedAt repository { nameWithOwner } headRefName headRefOid } }
    pageInfo { hasNextPage endCursor }
  }
}
"""

VIEWER_QUERY = "query { rateLimit { limit cost remaining nodeCount resetAt } viewer { login } }"

THREAD_QUERY = """
query($owner: String!, $repository: String!, $number: Int!) {
  rateLimit { limit cost remaining nodeCount resetAt }
  repository(owner: $owner, name: $repository) {
    pullRequest(number: $number) {
      isDraft
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      reviewThreads(first: 100) {
        nodes { isResolved comments(first: 100) { nodes { author { login } createdAt } } }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}
"""


def main():
    refs = fetch_refs(50)
    ten = refs[:10]
    # Synthesize the app's 50-ref worst case by cycling the refs we have.
    fifty = [(o, r, n, s) for (o, r, n, s) in (refs * 5)][:50]

    print("== batched pullRequestSummaries ==")
    for group, size in ((ten, "10 PR"), (fifty, "50 PR")):
        for variant, vlabel in (("old", "old(first:50)"), ("new50", "new(first:50)"), ("new100", "new(first:100)")):
            run(group, variant, f"{size} {vlabel}")

    print("\n== other poll calls ==")
    run_raw(VIEWER_QUERY, {}, "viewer")
    run_raw(SEARCH_QUERY, {"query": "is:pr is:open author:mdewadder org:dktunited"}, "search open PRs first:100")
    run_raw(SEARCH_QUERY, {"query": "is:pr is:merged author:mdewadder org:dktunited merged:>=2026-06-25"}, "search merged PRs first:100")
    run_raw(THREAD_QUERY, {"owner": "dktunited", "repository": "onepromotion", "number": 3013}, "reviewThreadState (100x100)")


if __name__ == "__main__":
    main()
