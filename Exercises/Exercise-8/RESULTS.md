# Exercise 8 results

Verified on 10 October 2026 using the Exercise 7 Jenkins 2.580.1 instance.

The `HelloWorld` Freestyle job checked out commit `011c78ac81d197cc64cce75c311dd47a478061fb` from this repository's `main` branch. Its Execute shell step ran the committed script and printed:

```text
+ sh Exercises/Exercise-8/hello-world.sh
Hello, Jenkins!
Finished: SUCCESS
```

Build 3 completed successfully. Five checks passed: Freestyle build type, Git repository/branch and checked-out revision, the real shell invocation, expected output and completed SUCCESS result. Earlier builds 1 and 2 also succeeded; the saved evidence is from build 3 after correcting the verification parser for Jenkins's XML 1.1 declaration.

- [Actual console output](evidence/console.txt)
- [Measured verification report](evidence/verification.json)
- [Authenticated console screenshot](evidence/hello-world-console.png)

The job is at http://127.0.0.1:18007/job/HelloWorld/. It is triggered manually, as in the source exercise. The source's separate sample repository was not created because this lab keeps all work in `DevOps-Lab`.
