import json
import sys
import subprocess
import datetime
import urllib.request
import os

# Configuration
ZREPL_POD_SELECTOR = "app=zrepl-garage-push"
ZREPL_NAMESPACE = "backup-system"
ZREPL_CONFIG_PATH = "/etc/zrepl/zrepl.yaml"
HC_PING_URL = os.environ.get("HC_PING_URL")
MAX_AGE_SECONDS = 3600 * 2  # 2 hours

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
    job = jobs.get("prod_to_backups", {})
    
    # The job status is nested under the type ("push")
    push_status = job.get("push", {})
    if not push_status:
        print("Job 'prod_to_backups' (push) not found")
        return False

    replication = push_status.get("Replication", {})
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
    
    if check_replication(status):
        ping_healthchecks()
    else:
        print("Replication check failed")
        sys.exit(1)

if __name__ == "__main__":
    main()
