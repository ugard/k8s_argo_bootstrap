import json
import re
import sys
import subprocess
import datetime
import urllib.request
import os

# Configuration
ZREPL_POD_SELECTOR = "app=zrepl-garage-pull"
ZREPL_NAMESPACE = "backup-system"
ZREPL_CONFIG_PATH = "/etc/zrepl/zrepl.yaml"
HC_PING_URL = os.environ.get("HC_PING_URL")
MAX_AGE_SECONDS = 3600 * 2  # 2 hours

# zrepl snapshoty nazywają się zrepl_<UTC timestamp>, np. zrepl_20260723_141500_000
# (prefix zrepl_ + %Y%m%d_%H%M%S_%f). Wzorzec wyłapuje je gdziekolwiek w statusie.
SNAPSHOT_NAME_RE = re.compile(r"zrepl_(\d{8}_\d{6}_\d{3})")

def get_zrepl_pod():
    cmd = ["kubectl", "get", "pods", "-n", ZREPL_NAMESPACE, "-l", ZREPL_POD_SELECTOR, "-o", "jsonpath={.items[0].metadata.name}"]
    try:
        result = subprocess.check_output(cmd).decode("utf-8").strip()
        return result
    except subprocess.CalledProcessError as e:
        print(f"Error getting zrepl pod: {e}")
        sys.exit(1)

def get_zrepl_status(pod_name):
    cmd = ["kubectl", "exec", "-n", ZREPL_NAMESPACE, pod_name, "--", "zrepl", "status", "--mode", "raw", "--config", ZREPL_CONFIG_PATH]
    try:
        result = subprocess.check_output(cmd).decode("utf-8")
        return json.loads(result)
    except subprocess.CalledProcessError as e:
        print(f"Error getting zrepl status: {e}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON: {e}")
        sys.exit(1)

def check_replication(status):
    jobs = status.get("Jobs", {})
    job = jobs.get("garage_pull", {})

    # The job status is nested under the type ("pull")
    pull_status = job.get("pull", {})
    if not pull_status:
        print("Job 'garage_pull' (pull) not found")
        return False

    replication = pull_status.get("Replication", {})
    attempts = replication.get("Attempts", [])
    
    if not attempts:
        print("No replication attempts found")
        return False

    # Get the last attempt
    last_attempt = attempts[-1]
    
    state = last_attempt.get("State")
    if state != "done":
        print(f"Last attempt state is '{state}', not 'done'")
        # We might still want to check the time of the last *successful* one if this one failed?
        # But for now, let's assume we want the last attempt to be done.
        # Actually, if it's "error", we should fail.
        return False

    last_run_time_str = last_attempt.get("FinishAt")
    if not last_run_time_str:
        print("No finish time found for last attempt")
        return False

    # Parse timestamp (RFC3339)
    # Handle 'Z' manually
    if last_run_time_str.endswith('Z'):
        last_run_time_str = last_run_time_str[:-1] + '+00:00'
    
    try:
        last_run_time = datetime.datetime.fromisoformat(last_run_time_str)
    except ValueError as e:
        print(f"Error parsing timestamp {last_run_time_str}: {e}")
        return False

    now = datetime.datetime.now(datetime.timezone.utc)
    age = (now - last_run_time).total_seconds()
    
    print(f"Last successful run: {last_run_time} (Age: {age} seconds)")
    
    if age > MAX_AGE_SECONDS:
        print(f"Replication is too old (> {MAX_AGE_SECONDS} seconds)")
        return False

    return True

def _iter_snapshot_names(obj):
    # Rekursywnie przechodzimy status i zbieramy wszystkie nazwy snapshotów zrepl_.
    # Nazwy From/To siedzą w Attempts[].Filesystems[].Steps[].Info, ale struktura
    # bywa różna między wersjami zrepl, więc skanujemy cały obiekt zamiast trzymać
    # się sztywnej ścieżki.
    if isinstance(obj, str):
        for m in SNAPSHOT_NAME_RE.finditer(obj):
            yield m.group(1)
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from _iter_snapshot_names(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _iter_snapshot_names(v)

def check_snapshot_freshness(status):
    # Wykrywa zatrzymanie snapshotowania na source (garage_source). Job garage_pull
    # jedzie na własnym interwale 10m i raportuje State=done nawet gdy source nie
    # wyprodukował żadnego nowego snapshotu (np. zfs snapshot się wywala a daemon
    # żyje) — sam check_replication zostałby wtedy zielony. Skoro źródło robi snapshot
    # co 10m, najnowszy widoczny w statusie pull snapshot zrepl_ nie powinien być
    # starszy niż ~1-2h.
    jobs = status.get("Jobs", {})
    job = jobs.get("garage_pull", {})
    pull_status = job.get("pull", {})
    if not pull_status:
        print("Job 'garage_pull' (pull) not found (snapshot freshness)")
        return False

    timestamps = []
    for raw in _iter_snapshot_names(pull_status):
        try:
            # Handle 'Z' manually — tu format to zrepl_%Y%m%d_%H%M%S_%f w UTC,
            # więc doklejamy strefę ręcznie po sparsowaniu.
            ts = datetime.datetime.strptime(raw, "%Y%m%d_%H%M%S_%f")
            timestamps.append(ts.replace(tzinfo=datetime.timezone.utc))
        except ValueError as e:
            print(f"Error parsing snapshot timestamp {raw}: {e}")

    if not timestamps:
        print("No zrepl_ snapshots found in pull status (source may be stalled)")
        return False

    newest = max(timestamps)
    now = datetime.datetime.now(datetime.timezone.utc)
    age = (now - newest).total_seconds()

    print(f"Newest replicated snapshot: zrepl_{newest.strftime('%Y%m%d_%H%M%S_%f')[:-3]} (Age: {age} seconds)")

    if age > MAX_AGE_SECONDS:
        print(f"Newest snapshot is too old (> {MAX_AGE_SECONDS} seconds) — source snapshotting likely stalled")
        return False

    return True

def ping_healthchecks():
    if not HC_PING_URL:
        print("HC_PING_URL not set")
        return

    try:
        urllib.request.urlopen(HC_PING_URL, timeout=10)
        print("Pinged Healthchecks.io successfully")
    except Exception as e:
        print(f"Error pinging Healthchecks.io: {e}")

def main():
    pod_name = get_zrepl_pod()
    print(f"Found zrepl pod: {pod_name}")
    
    status = get_zrepl_status(pod_name)

    # Oba warunki muszą przejść: (1) ostatnia próba replikacji się zakończyła i jest
    # świeża, (2) najnowszy zreplikowany snapshot jest świeży (łapie stall snapshotów
    # na source, którego samo (1) by nie wykryło).
    if check_replication(status) and check_snapshot_freshness(status):
        ping_healthchecks()
    else:
        print("Replication check failed")
        sys.exit(1)

if __name__ == "__main__":
    main()
