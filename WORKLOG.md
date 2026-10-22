# Worklog

## Week 1 [2026-10-15 - 2026-10-22]

## Setup
* Installed .NET SDK 8.0.428
* Installed Docker

## 2026-10-19 - Orion Kinsler
* **Part 1: Scaffold**
    * [x] Scaffold ASP .NET Core Web API
        >  Environment required .NET 8 SDK. Used `dotnet new webapi -n OrderService --use-controllers false` with the `--framework net8.0` option to force .NET 8.0.
        > First commit had no `.gitignore`, so `bin/` and `obj/` were tracked, had to untrack binary and object files. Fixed by adding `.gitignore` and using `git rm -r --cached` to untrack files.
    * [x] Add `GET /health` and `GET /version` in `Program.cs` with `app.MapGet`
        > `/version` reads `APP_VERSION` and defaults to `dev`.
    * [x] Run locally and curl endpoints

* **Part 2: Vulnerability**
    * [x] Package vulnerabilities
        > `dotnet list package --vulnerable --include-transitive` was clean at first. After adding Newtonsoft.Json 9.0.1 reported a High Severity finding.
    * [x] Build multistage Dockerfile
    * [x] Scan docker image using 'Trivy'
        > SDK base image was used for runtime resulting in Trivy showing 427 findings (80 High, 1 Critical), including sdk tooling. Fixed by swapping base image to `aspnet:8.0` image.
        > After swapping to `aspnet:8.0` base image Trivy findings dropped to 255 however, Critical findings went up to 4. Fixed by adding package updates with `apt-get update && apt-get upgrade -y` to the runtime stage.
            > Note: Builds are less reproducible, based on published packages.
    * [x] Fix vulnerable package
        > Updated Newtonsoft.Json to version 13.0.1 resulting in trivy showing 0 (High, Critical) vulnerabilities.

    ***Notes***
    > `curl localhost:8080` failed to connect when the container ran, logs showed the app listening on 8080 inside the container, but I hadn’t published the port. Fixed with `-p 8080:8080`.

    **Question**
    * Why do we care if the container runs as root, and what did you have to change to make USER appuser actually work?
        > A container with root access creates a vulnerability, a container with root access could allow an attacker to escape the container or access or damage volumes on the host. During this project I did not have to make any changes to make `appuser` work, I verified `appuser` using `docker exec check whoami`, any and all actions that required root access were executed before swapping to app user. The only things that needed to be in place for `appuser` to work was for `appuser` to exist which was done using `adduser --disabled-password --gecos "" appuser`, all commands requiring root access including the ones I added were executed before swapping to `appuser` using `USER`. Lastly the user doesn't need elevated privelages as the app listens on port 8080 which is high enough to not require additional permissiona and the user does not need to write to `/app`.

* **Part 3: Actions**
    * [x] `ci.yml` triggers on push and PR to the default branch
        > First push did not trigger a workflow. Fixed by swapping default workflow and `github.ref` branch from `main` to `master`.
    * [x] `workflow_dispatch` with a `redeploy_only` boolean
    * [x] Jobs: `format-and-test` -> `docker-build-and-scan` -> `push` -> `deploy`, chained with `needs:`
        > Format check failed due to a  whitespace formatting error flagged by `dotnet format --verify-no-changes` in `Program.cs` (lines 26 and 39). Commited fix.
        > last step of `format-and-test` used `--include-transative`. Fixed by correcting to `--include-transitive`.
        > login then failed with `Cannot perform an interactive login from a non TTY device`. Fixed by creating a personal access token with `write:packages` and stored it as the `GHCR_TOKEN` repo secret.
        > Registry push or build failed with an invalid reference. Fixed by lowercasing the registry path
    * [x] Dependency scan report / Trivy as a gate
    * [x] Caching: NuGet (`actions/cache`, keyed on a hash of `*.csproj`) and Docker layers (`type=gha`)
            
    ***Notes***
    * Needed to update packages and install curl package in docker runtime build
    > Added workflow to .dockerignore to reduce build context

## 2026-10-20 - Orion Kinsler
* **Part 4: Deploy**
    * [x] Deploy job pulls the image for the commit SHA, removes any existing, and runs the new container, then verifies `/version`.
        > `docker pull` failed with `unauthorized`, each container runs on a fresh vm so authorization defined in `push` did not carry over. Fixed by adding GHCR authorization step to deploy job.
        > Exited with code 1 on a fresh runner. Fixed by adding `|| true` to each command would run.
        > Version check failed with `Connection reset by peer`. Fixed using a retry loop around the curl.
        > Deploy kept running after upstream jobs failed. Fixed by replacing `always()` with `!cancelled()`.
    * [x] Ran on the Actions runner
    * [x] `redeploy_only` verified

    **Question**
    * What's the actual risk of docker run with no restart policy and no health-based rollback, and what's the smallest change that reduces it?
        > If `docker run` has no restart policy by default, if a crash happens or the host reboots your container will stay down, unless restarted manually. This can lead to services being down until someone manually restarts them and can cause extended downtimes, a small change to reduce this risk would be to use `--restart unless-stopped` which would restart the container in the case of a crash or a host reboot. Currently my deploy job removes the old container before the new one is verified, so a bad release leaves no working service, and nothing automatically restores the previous version.

* **Part 5: Q&A**
    * Format check, test, security scan — if all three could run in parallel instead of sequentially, would you? What do you gain, what do you risk?
        > Currently I would not parallelize them. Running them in parallel would shorten the total run time to the slowest job instead of the sum of all of them, one push would also report every failure at once however, cost is wasted runner time and more noise. If the format check fails after a few seconds, the image build and scan would still run to completion, and each extra job pays for its own runner startup. Since the format check is cheap and the most common failure, I kept `format-and-test` first and made `docker-build-and-scan` depend on it with `needs:`, so a formatting error fails fast and never starts the expensive build. If run time became a problem, the first change I'd make is removing that `needs:` so the Docker build runs alongside the tests.

    * Where do secrets live in your pipeline? What's the blast radius if one leaks into a log line?
        > Secrets in my pipeline live as a secret stored as a repository secret under `settings` -> `secrets and variables` -> `actions`, currently only the `push` and `deploy` jobs use it. The secret is encrypted by GitHub, masked as `***` in the logs, and can be accessed by `${{ secrets.GHCR_TOKEN }}`. Currently my secret is a classic personal access token with `write:packages` and `repo` which would give access to read and write permissions to all of my repos, and could be used to push a malicious image to project, currently it only lasts for 30 days. Alternatively I could use a `GITHUB_TOKEN` to limit the scope to this specific repo.

    * Your Trivy gate uses --ignore-unfixed. A base-image CVE that had no fix gets one next month. Nothing in your pipeline catches that automatically. What's the gap, how do you close it?
        > Currently the pipeline only runs on push and PR events, this only scans vulnerabilities when changes are commited to the branch. If a known vulnerability becomes fixable during these periods then the image would keep running with a known and fixable vulnerability. One way we could close this gap would be to add a `schedule:` trigger and run a security job that would scan for fixable vulnerabilities.

    * If this needed 3 replicas behind a load balancer instead of one docker run, what's the smallest realistic next step — and what would you explicitly not try to solve with a Dockerfile change alone?
        > The smallest realistic next step is to run the same image as three replicas with `docker compose` behind a reverse proxy so only the proxy publishes a port and traffic is spread across the replicas. The current container has both a fixed name and port only allowing for one container, a change to the Dockerfile would be unable to fix this. A Dockerfile only defines one container’s contents and would not be able to solve how many copies run or where.