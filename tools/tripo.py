"""
Generate models (and concept images) with the Tripo API directly.

    python tools/tripo.py balance
    python tools/tripo.py run tools/tripo_jobs.json [--only Name,Name] [--redo Name,Name] [--dry]

Needs TRIPO_API_KEY (starts with tsk_). API credits are separate from the tripo3d.ai
web app's credits; top up at platform.tripo3d.ai.

Each job in the jobs file is one of:
    {"name": "Geodeer", "group": "juveniles", "type": "image_to_model", "image": "<png url or local path>"}
    {"name": "HollowStump", "group": "props", "type": "text_to_model", "prompt": "..."}
    {"name": "Kelpotter", "group": "concepts", "type": "generate_image", "ref": "<url>", "prompt": "..."}

Settings match the old Higgsfield pipeline (tripo_h3_1_image_to_3d): v3.1, 8000 faces,
standard texture with PBR. Costs (2026-09): image_to_model 30, text_to_model 20,
generate_image 5-10 credits.

Outputs land in assets/tripo/<group>/ (gitignored): <Name>.glb plus <Name>_preview.webp
for models, <Name>.png for concept images. Every submitted task is recorded in
tools/tripo_log.json, and a job that already succeeded is skipped (no double spend)
unless it's listed in --redo. Tripo's download links expire after a few minutes, so
outputs are fetched right away; host the GLBs somewhere durable before adding them to
tools/assets_manifest.json (see docs/ASSETS.md).
"""

import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
API = "https://api.tripo3d.ai/v2/openapi"
LOG_PATH = ROOT / "tools/tripo_log.json"
OUT_ROOT = ROOT / "assets/tripo"
MAX_RUNNING = 8  # the API allows 10 concurrent model tasks per account

MODEL_SETTINGS = {
    "model_version": "v3.1-20260211",
    "face_limit": 8000,
    "texture": True,
    "pbr": True,
    "texture_quality": "standard",
}
IMAGE_MODEL = "gpt_4o"  # 5 credits; gpt_image_2 / gemini_3_pro_image_preview cost 10


def api_key() -> str:
    key = os.environ.get("TRIPO_API_KEY", "")
    if not key.startswith("tsk_"):
        sys.exit("Set TRIPO_API_KEY (starts with tsk_).")
    return key


def request(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{API}{path}", data=data, method=method)
    req.add_header("Authorization", f"Bearer {api_key()}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            payload = json.loads(response.read())
    except urllib.error.HTTPError as error:
        payload = json.loads(error.read() or b"{}")
    if payload.get("code") != 0:
        raise RuntimeError(f"{payload.get('code')}: {payload.get('message')} {payload.get('suggestion', '')}")
    return payload["data"]


def upload_image(path: pathlib.Path) -> dict:
    boundary = uuid.uuid4().hex
    kind = "png" if path.suffix.lower() == ".png" else "jpeg"
    body = (
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{path.name}"\r\n'
        f"Content-Type: image/{kind}\r\n\r\n"
    ).encode() + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(f"{API}/upload/sts", data=body, method="POST")
    req.add_header("Authorization", f"Bearer {api_key()}")
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    with urllib.request.urlopen(req, timeout=120) as response:
        payload = json.loads(response.read())
    if payload.get("code") != 0:
        raise RuntimeError(f"upload failed: {payload}")
    return {"type": kind, "file_token": payload["data"]["image_token"]}


def image_input(source: str) -> dict:
    if source.startswith("http"):
        kind = "png" if source.lower().endswith(".png") else "jpg"
        return {"type": kind, "url": source}
    path = pathlib.Path(source)
    if not path.is_absolute():
        path = ROOT / path
    return upload_image(path)


def task_body(job: dict) -> dict:
    kind = job["type"]
    if kind == "image_to_model":
        return {"type": kind, "file": image_input(job["image"]), **MODEL_SETTINGS, **job.get("settings", {})}
    if kind == "text_to_model":
        body = {"type": kind, "prompt": job["prompt"], **MODEL_SETTINGS, **job.get("settings", {})}
        if job.get("negative_prompt"):
            body["negative_prompt"] = job["negative_prompt"]
        return body
    if kind == "generate_image":
        body = {"type": kind, "prompt": job["prompt"], "model_version": job.get("model", IMAGE_MODEL)}
        if job.get("ref"):
            body["file"] = image_input(job["ref"])
        return body
    raise ValueError(f"unknown job type {kind}")


def download(url: str, out: pathlib.Path):
    out.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "hatch-and-snatch-assets"})
    with urllib.request.urlopen(req, timeout=300) as response:
        out.write_bytes(response.read())


def save_outputs(job: dict, task: dict) -> list[str]:
    output = task.get("output", {})
    folder = OUT_ROOT / job["group"]
    saved = []
    if job["type"] == "generate_image":
        url = output.get("generated_image")
        if url:
            ext = ".png" if ".png" in url.split("?")[0] else ".jpg"
            download(url, folder / f"{job['name']}{ext}")
            saved.append(f"{job['name']}{ext}")
        return saved
    model_url = output.get("pbr_model") or output.get("model") or output.get("base_model")
    if model_url:
        download(model_url, folder / f"{job['name']}.glb")
        saved.append(f"{job['name']}.glb")
    if output.get("rendered_image"):
        download(output["rendered_image"], folder / f"{job['name']}_preview.webp")
        saved.append(f"{job['name']}_preview.webp")
    return saved


def load_log() -> dict:
    return json.loads(LOG_PATH.read_text()) if LOG_PATH.exists() else {}


def record(key: str, entry: dict):
    # Re-read before writing so two runs at once don't drop each other's entries
    log = load_log()
    log[key] = entry
    LOG_PATH.write_text(json.dumps(log, indent=1, sort_keys=True) + "\n")


def run(jobs_path: str, only: set[str], redo: set[str], dry: bool):
    spec = json.loads(pathlib.Path(jobs_path).read_text())
    jobs = [j for j in spec["jobs"] if not only or j["name"] in only]
    log = load_log()
    pending = []
    for job in jobs:
        key = f"{job['group']}/{job['name']}"
        entry = log.get(key)
        if entry and entry.get("status") == "success" and job["name"] not in redo:
            continue
        if entry and entry.get("status") in ("queued", "running") and job["name"] not in redo:
            pending.append((job, entry["task_id"]))  # resume polling a task from an interrupted run
            continue
        pending.append((job, None))
    print(f"{len(pending)} job(s) to run; balance {request('GET', '/user/balance')['balance']}")
    if dry:
        for job, task_id in pending:
            print(f"  {job['group']}/{job['name']} ({job['type']})" + (f" resume {task_id}" if task_id else ""))
        return

    running: dict[str, dict] = {}
    queue = list(pending)
    spent = 0
    while queue or running:
        while queue and len(running) < MAX_RUNNING:
            job, task_id = queue.pop(0)
            key = f"{job['group']}/{job['name']}"
            if task_id is None:
                try:
                    task_id = request("POST", "/task", task_body(job))["task_id"]
                except Exception as error:
                    if str(error).startswith(("2000:", "1007:")):  # rate limited: retry later
                        queue.insert(0, (job, None))
                        break
                    print(f"  SUBMIT FAILED {key}: {error}")
                    record(key, {"status": "submit_failed", "error": str(error)})
                    continue
                print(f"  submitted {key}: {task_id}")
            record(key, {"task_id": task_id, "status": "queued", "type": job["type"]})
            running[task_id] = job
        time.sleep(5)
        for task_id, job in list(running.items()):
            key = f"{job['group']}/{job['name']}"
            try:
                task = request("GET", f"/task/{task_id}")
            except Exception as error:
                print(f"  poll error {key}: {error}")
                continue
            status = task.get("status")
            if status in ("queued", "running"):
                continue
            del running[task_id]
            entry = {"task_id": task_id, "status": status, "type": job["type"], "credits": task.get("consumed_credit", 0)}
            if status == "success":
                try:
                    entry["files"] = save_outputs(job, task)
                except Exception as error:  # links expire: re-fetch the task for fresh ones and retry once
                    try:
                        entry["files"] = save_outputs(job, request("GET", f"/task/{task_id}"))
                    except Exception:
                        entry["status"] = "download_failed"
                        entry["error"] = str(error)
            spent += entry["credits"] or 0
            record(key, entry)
            print(f"  {status:8} {key} ({entry['credits']} credits) {', '.join(entry.get('files', []))}")
    print(f"done; spent {spent} credits, balance {request('GET', '/user/balance')['balance']}")


def main():
    args = sys.argv[1:]
    if not args or args[0] == "balance":
        print(request("GET", "/user/balance"))
        return
    if args[0] == "run" and len(args) >= 2:

        def names(flag: str) -> set[str]:
            return set(args[args.index(flag) + 1].split(",")) if flag in args else set()

        run(args[1], names("--only"), names("--redo"), "--dry" in args)
        return
    sys.exit(__doc__)


if __name__ == "__main__":
    main()
