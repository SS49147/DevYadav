# Exercise 8: Hello World Jenkins Job

Follow [Sunag's Hello World exercise](https://github.com/SunagP/DevOps-Lab/blob/main/Exercises/8-Jenkins-Hello-World-Job.md): commit a shell script, configure a Freestyle job with Git SCM, run it and inspect the output.

The script retains the source's `Hello, Jenkins!` message. It stays in this repository instead of creating `devops-sample-code`, as selected for this lab. Jenkins checks out `https://github.com/Anas2694/DevOps-Lab.git`, branch `main`, and runs the script's folder path. Existing authenticated Git tooling handles pushes; public Jenkins checkout does not require a new personal access token.

## Run

First complete [Exercise 7](../Exercise-7/README.md). Keep that Jenkins instance running and its administrator password file in place. Commit and push this exercise before running the job so Git SCM can fetch the script.

Use PowerShell 7 from this folder:

```powershell
./run_job.ps1
```

The script creates the `HelloWorld` Freestyle job from `job.xml`, starts a manual build, waits for completion and saves the real console and verification report under `evidence/`. It refuses to replace an existing job with a different description. It does not enable a webhook or automatic Jenkins build trigger.

For manual configuration at http://127.0.0.1:18007:

1. Create a Freestyle project named `HelloWorld`.
2. Use description `Exercise 8: Hello World! Jenkins job.`
3. Select Git SCM, enter this repository's URL and choose `*/main`.
4. Add Execute shell with `sh Exercises/Exercise-8/hello-world.sh`.
5. Save, click Build Now, then open the build's Console Output.

The console must show the expected message followed by `Finished: SUCCESS`. The verification also checks the job type, SCM configuration and actual shell invocation. The GitHub workflow starts a fresh Exercise 7 Jenkins instance and repeats this Freestyle build.

Generated browser sessions are ignored under `.secrets/`. Jenkins credentials remain in Exercise 7's ignored folder; neither belongs in Git.

See [RESULTS.md](RESULTS.md) for the measured build, console and screenshot.
