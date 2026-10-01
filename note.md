# DAM Core Philosophy

**Goal:** Stop reinventing the Docker CLI.

The core value of `dam` is **application lifecycle management** (`start`, `stop`, `update`, `recreate`, `delete` for specific app stacks). It saves time by automatically finding the right directory, pulling the right images, and managing the Compose deployment safely.

### The "Anti-Wrapper" Rule
`dam` should **not** wrap global Docker maintenance tasks just to save users from typing `docker`. If a feature is simply a 1-to-1 mapping of an existing Docker command, it does not belong in `dam`.

**Anti-Patterns (Things to Avoid):**
- **Advanced Cleanup Wrappers:** The current `cleanup` command (which does simple, basic maintenance) is sufficient. Dam will **never expand it** to support advanced custom flags (like `--builder` or `--filter`). For anything beyond the simple defaults, users must rely on native `docker prune` commands.
- **Global Resource Management:** Dam will **never** add wrappers for `docker network create` or `docker volume create`.
- **Registry & Image Management:** Dam will **never** wrap `docker login`, `docker push`, or standalone `docker build` commands. 

My Philosophy is **Keep it simple**. Let *Docker be Docker*, and let `dam` manage the apps for daily commands that require long paths or cd-ing and many multi-command steps just to complete simple tasks like updating a stack, recreating containers safely, or tearing down an application.
