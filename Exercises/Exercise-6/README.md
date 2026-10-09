# Exercise 6: Delivery Monitoring with Prometheus and Grafana

Implement [Sunag's monitoring exercise](https://github.com/SunagP/DevOps-Lab/blob/main/Exercises/6-Grafana-Realtime-Monitoring-of-Quick-Commerce-App.md): simulate deliveries, collect four metrics, show them in Grafana, define alert rules, and deploy the services through Jenkins.

Measured build results, checks and screenshots are in [RESULTS.md](RESULTS.md).

## Run the lab

Docker Desktop must be running. Use PowerShell 7 from this folder:

```powershell
./start.ps1
./run_pipeline.ps1 -Mode normal
./verify.ps1 -Mode normal
```

The first command builds Jenkins with the Pipeline and Git plugins, creates an administrator account, and starts a dedicated Docker-in-Docker daemon. The daemon requires privileged mode for this local lab. Jenkins connects using TLS; it does not mount the laptop's Docker socket. Its builds manage only containers inside that separate daemon. The daemon's TLS port is not published to the host. This follows the [Jenkins Docker installation guide](https://www.jenkins.io/doc/book/installing/docker/).

Generated administrator passwords are stored in the ignored `.secrets/jenkins-admin` and `.secrets/grafana-admin` files. Use username `admin` to sign in; view the appropriate password file locally if needed. Do not upload these files. Grafana also allows a read-only anonymous viewer on its loopback-bound lab port.

| Service | Local address |
| --- | --- |
| Jenkins | http://127.0.0.1:18006 |
| Simulator metrics | http://127.0.0.1:18000/metrics |
| Prometheus | http://127.0.0.1:13906 |
| Grafana dashboard | http://127.0.0.1:13006/d/delivery-monitoring/delivery-monitoring |

Host ports differ from the source to avoid earlier assignments and existing applications. Inside the dedicated daemon, the simulator, Prometheus and Grafana still use ports 8000, 9090 and 3000.

## Jenkins pipeline

`run_pipeline.ps1` creates or updates the `DeliveryMonitoring` job from `Jenkinsfile`, selects the scenario, starts a build, waits for completion, and saves the real console output and build result under `evidence/`.

The five stages perform the source's workflow:

1. Pre-check Docker: confirm the CLI can reach the dedicated daemon.
2. Setup Workspace: copy this folder's application and monitoring configuration into the Jenkins workspace.
3. Build Docker Image: build all three images, run the Python tests and validate the Prometheus configuration with `promtool`.
4. Run Application: start the simulator on the `delivery_monitoring` network.
5. Run Prometheus & Grafana: start both monitoring services with their saved configuration.

Each rerun replaces only the three lab-owned containers. Container and network ownership labels are checked before replacement. The Jenkins workspace volume is shared with the dedicated daemon so Grafana can read its password file without putting the password into an image or command argument.

## Metrics and alerts

The simulator updates once per second. Normal values follow the source: pending deliveries 10–20, on-the-way deliveries 5–20, delivered orders 30–70, and delivery time 15–45 seconds. Total deliveries is their count sum. Average delivery time is a Prometheus Summary; the dashboard uses `average_delivery_time_sum / average_delivery_time_count`, the cumulative observed mean since application startup.

Prometheus scrapes itself and `delivery_metrics:8000` every five seconds. Grafana uses `http://prometheus:9090`. Container DNS names replace the source's host IP/localhost targets because these services run on the same Docker network. Configuration is baked into the monitoring images to avoid Windows bind-path differences. Four time-series panels display the required metrics; a separate table displays currently firing Prometheus alerts.

The rules retain the source's expressions and labels:

| Alert | Condition | Hold time | Severity |
| --- | --- | --- | --- |
| HighPendingDeliveries | `pending_deliveries > 10` | 15 seconds | warning |
| HighAverageDeliveryTime | `average_delivery_time_sum / average_delivery_time_count > 30` | none | critical |

The average-time rule has no `for` in the source YAML, so its description does not claim a 15-second hold. The source's final paragraph calls the pending-delivery alert critical, but its rule defines warning; the rule is retained. Normal random values can also trigger these low thresholds. No external notification destination or Alertmanager is configured.

Run the required high-pending test:

```powershell
./run_pipeline.ps1 -Mode high_pending
./verify.ps1 -Mode high_pending
```

This changes pending deliveries to 50–100 and restarts the application and monitoring containers. Delivery time retains the original 15–45-second range. For a repeatable check of both rules, the additional `high_pending_slow` mode uses the same pending range and delivery times of 35–45 seconds:

```powershell
./run_pipeline.ps1 -Mode high_pending_slow
./verify.ps1 -Mode high_pending_slow
```

The verification script checks metric ranges, increasing observations, both scrape targets, all four dashboard queries through Grafana, rule definitions and firing alerts. Reports and console logs are also uploaded by the Exercise 6 GitHub workflow.

## Stop without deleting lab data

```powershell
docker compose down
```

This stops only this Compose project. Its named volumes retain Jenkins jobs and the dedicated Docker daemon's images. Keep `.secrets/` when restarting with those volumes so the same credentials remain available.
