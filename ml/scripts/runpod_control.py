"""Drive an unattended RunPod job over HTTPS only (GraphQL API + the pod's Jupyter contents API).

    export RUNPOD_API_KEY=...
    python scripts/runpod_control.py create --gpu "NVIDIA GeForce RTX 4090" --disk 80 --env OPENROUTER_API_KEY=... --job scripts/runpod_job.sh
    python scripts/runpod_control.py status POD_ID
    python scripts/runpod_control.py log POD_ID --tail 60
    python scripts/runpod_control.py download POD_ID workspace/results.tar.gz results.tar.gz
    python scripts/runpod_control.py terminate POD_ID
    python scripts/runpod_control.py list

A job with extra inputs: `create` without --job, then `pack ml ml.tar.gz`, `upload`/`mkdir` the inputs into
workspace/, and upload the job file last (`upload POD_ID scripts/runpod_job_vlm_real.sh workspace/job.sh`).

The pod's start command waits for /workspace/job.sh to appear, then runs it; `create` uploads the
code tarball and the job through Jupyter (token = a random secret passed as JUPYTER_PASSWORD).
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import os
import secrets
import subprocess
import sys
import tarfile
import time
from pathlib import Path

import requests

API = "https://api.runpod.io/graphql"
IMAGE = "runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04"
START_CMD = ("bash -c '/start.sh & sleep 15; while [ ! -f /workspace/job.sh ]; do sleep 5; done; "
             "cd /workspace && bash job.sh > /workspace/job.log 2>&1'")


def gql(query: str, variables: dict | None = None) -> dict:
    key = os.environ["RUNPOD_API_KEY"]
    r = requests.post(f"{API}?api_key={key}", json={"query": query, "variables": variables or {}}, timeout=60)
    r.raise_for_status()
    data = r.json()
    if data.get("errors"):
        raise RuntimeError(json.dumps(data["errors"])[:800])
    return data["data"]


def build_code_tar(code_dir: str) -> bytes:
    root = Path(code_dir).resolve()
    if not (root / "pyproject.toml").exists():
        raise SystemExit(f"{root} is not the ml package directory (no pyproject.toml)")
    buf = io.BytesIO()
    n = 0
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for p in root.rglob("*"):
            rel = p.relative_to(root.parent)
            top = rel.parts[1] if len(rel.parts) > 1 else ""
            if any(part in ("__pycache__", ".pytest_cache", ".venv") for part in rel.parts) or top in ("data", "runs", "results") or p.suffix == ".pyc":
                continue   # skip caches and the top-level data/runs/results dirs, never package sub-directories
            tar.add(p, arcname=str(rel), recursive=False)
            n += p.is_file()
    data = buf.getvalue()
    if n < 20 or len(data) < 10_000:
        raise SystemExit(f"code tarball looks wrong: {n} files, {len(data)} bytes")
    print(f"code tarball: {n} files, {len(data)} bytes")
    return data


def create(args) -> None:
    code = build_code_tar(args.code) if args.job else b""
    token = secrets.token_hex(16)
    env = [{"key": "JUPYTER_PASSWORD", "value": token}, {"key": "RUNPOD_API_KEY", "value": os.environ["RUNPOD_API_KEY"]}]
    for kv in args.env:
        k, v = kv.split("=", 1)
        env.append({"key": k, "value": v})
    query = """
    mutation Deploy($input: PodFindAndDeployOnDemandInput!) {
      podFindAndDeployOnDemand(input: $input) { id imageName machineId costPerHr machine { podHostId gpuDisplayName } }
    }"""
    variables = {"input": {
        "cloudType": args.cloud, "gpuCount": 1, "volumeInGb": 0, "containerDiskInGb": args.disk,
        "minVcpuCount": args.vcpu, "minMemoryInGb": args.ram, "gpuTypeId": args.gpu, "name": args.name,
        "imageName": args.image, "dockerArgs": START_CMD, "ports": "8888/http,22/tcp", "volumeMountPath": "/workspace",
        "env": env, "startJupyter": False, "startSsh": False,
    }}
    pod = gql(query, variables)["podFindAndDeployOnDemand"]
    print(json.dumps({"pod": pod, "jupyter_token": token}))
    state = {"pod_id": pod["id"], "token": token, "created": time.time()}
    Path(args.state).write_text(json.dumps(state))
    if args.job:
        wait_ready(pod["id"], token, args.wait)
        upload_bytes(pod["id"], token, "workspace/ml.tar.gz", code)
        upload_text(pod["id"], token, "workspace/job.sh", Path(args.job).read_text())
        print("job uploaded; the pod starts it within seconds")


PREFIX: dict[str, str] = {}   # pod id -> "workspace/" when Jupyter serves from /, "" when it serves /workspace


def pod_url(pod_id: str, path: str, token: str) -> str:
    prefix = PREFIX.get(pod_id, "workspace/")
    if path.startswith("workspace/"):
        path = prefix + path[len("workspace/"):]
    return f"https://{pod_id}-8888.proxy.runpod.net/api/contents/{path}?token={token}"


def detect_root(pod_id: str, token: str) -> bool:
    """Finds which contents path reaches /workspace; True when Jupyter answered at all."""
    for prefix in ("workspace/", ""):
        try:
            r = requests.get(f"https://{pod_id}-8888.proxy.runpod.net/api/contents/{prefix.rstrip('/')}?token={token}", timeout=20)
        except requests.RequestException:
            return False
        if r.status_code == 200 and (prefix == "" or r.json().get("type") == "directory"):
            PREFIX[pod_id] = prefix
            return True
    return False


def wait_ready(pod_id: str, token: str, wait_s: int) -> None:
    started = time.time()
    while time.time() - started < wait_s:
        if detect_root(pod_id, token):
            print(f"jupyter ready after {int(time.time() - started)} s (contents prefix {PREFIX[pod_id]!r})")
            return
        time.sleep(15)
    raise SystemExit("pod's Jupyter did not come up in time; check `status`")


def mkdir(pod_id: str, token: str, path: str) -> None:
    r = requests.put(pod_url(pod_id, path, token), json={"type": "directory"}, timeout=60)
    if r.status_code not in (200, 201):
        r.raise_for_status()


def upload_text(pod_id: str, token: str, path: str, content: str) -> None:
    r = requests.put(pod_url(pod_id, path, token), json={"type": "file", "format": "text", "content": content}, timeout=60)
    r.raise_for_status()
    print("uploaded", path, r.status_code)


def upload_bytes(pod_id: str, token: str, path: str, data: bytes) -> None:
    r = requests.put(pod_url(pod_id, path, token), json={"type": "file", "format": "base64", "content": base64.b64encode(data).decode()}, timeout=300)
    r.raise_for_status()
    print("uploaded", path, len(data), "bytes")


def read_text(pod_id: str, token: str, path: str) -> str:
    r = requests.get(pod_url(pod_id, path, token) + "&type=file&format=text", timeout=60)
    r.raise_for_status()
    return r.json().get("content") or ""


def download(pod_id: str, token: str, path: str, dest: str) -> None:
    r = requests.get(pod_url(pod_id, path, token) + "&type=file&format=base64", timeout=1800)
    r.raise_for_status()
    data = base64.b64decode(r.json()["content"])
    Path(dest).write_bytes(data)
    print("downloaded", dest, len(data), "bytes")


def status(pod_id: str) -> dict:
    query = """query Pod($id: String!) { pod(input: {podId: $id}) { id name desiredStatus costPerHr uptimeSeconds runtime { uptimeInSeconds gpus { gpuUtilPercent memoryUtilPercent } } machine { gpuDisplayName } } }"""
    return gql(query, {"id": pod_id})["pod"]


def list_pods() -> list:
    return gql("query { myself { pods { id name desiredStatus costPerHr uptimeSeconds machine { gpuDisplayName } } clientBalance } }")["myself"]


def terminate(pod_id: str) -> None:
    gql("mutation T($id: String!) { podTerminate(input: {podId: $id}) }", {"id": pod_id})
    print("terminate requested for", pod_id)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("create")
    c.add_argument("--gpu", default="NVIDIA GeForce RTX 4090")
    c.add_argument("--cloud", default="COMMUNITY", choices=["COMMUNITY", "SECURE", "ALL"])
    c.add_argument("--disk", type=int, default=80)
    c.add_argument("--vcpu", type=int, default=8)
    c.add_argument("--ram", type=int, default=30)
    c.add_argument("--image", default=IMAGE)
    c.add_argument("--name", default="photomesh-ml")
    c.add_argument("--env", action="append", default=[])
    c.add_argument("--job", default=None)
    c.add_argument("--code", default="ml")
    c.add_argument("--state", default="runpod_state.json")
    c.add_argument("--wait", type=int, default=900)
    for name in ("status", "terminate"):
        p = sub.add_parser(name)
        p.add_argument("pod_id")
    l = sub.add_parser("log")
    l.add_argument("pod_id")
    l.add_argument("--token", required=True)
    l.add_argument("--path", default="workspace/job.log")
    l.add_argument("--tail", type=int, default=40)
    d = sub.add_parser("download")
    d.add_argument("pod_id")
    d.add_argument("path")
    d.add_argument("dest")
    d.add_argument("--token", required=True)
    u = sub.add_parser("upload")
    u.add_argument("pod_id")
    u.add_argument("src")
    u.add_argument("path")
    u.add_argument("--token", required=True)
    m = sub.add_parser("mkdir")
    m.add_argument("pod_id")
    m.add_argument("path")
    m.add_argument("--token", required=True)
    k = sub.add_parser("pack", help="write the code tarball that `create --job` would upload, for jobs with extra inputs")
    k.add_argument("code")
    k.add_argument("dest")
    sub.add_parser("list")
    args = parser.parse_args()
    if args.cmd == "create":
        create(args)
    elif args.cmd == "pack":
        Path(args.dest).write_bytes(build_code_tar(args.code))
    elif args.cmd == "mkdir":
        detect_root(args.pod_id, args.token)
        mkdir(args.pod_id, args.token, args.path)
        print("created", args.path)
    elif args.cmd == "status":
        print(json.dumps(status(args.pod_id), indent=1))
    elif args.cmd == "terminate":
        terminate(args.pod_id)
    elif args.cmd == "list":
        print(json.dumps(list_pods(), indent=1))
    elif args.cmd == "log":
        detect_root(args.pod_id, args.token)
        text = read_text(args.pod_id, args.token, args.path)
        print("\n".join(text.splitlines()[-args.tail:]))
    elif args.cmd == "download":
        detect_root(args.pod_id, args.token)
        download(args.pod_id, args.token, args.path, args.dest)
    elif args.cmd == "upload":
        detect_root(args.pod_id, args.token)
        src = Path(args.src)
        if src.suffix in (".sh", ".py", ".txt", ".json", ".jsonl", ".md"):
            upload_text(args.pod_id, args.token, args.path, src.read_text())
        else:
            upload_bytes(args.pod_id, args.token, args.path, src.read_bytes())


if __name__ == "__main__":
    main()
