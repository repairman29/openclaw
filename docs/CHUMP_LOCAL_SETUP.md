# Chump local setup (Maclawd)

Chump is not part of the Maclawd repo. To use Chump, clone the canonical repo into **Projects/Chump** (sibling of Maclawd):

```bash
cd /Users/jeffadkins/Projects
rm -rf Chump
git clone https://github.com/repairman29/chump.git Chump
```

That gives you **`~/Projects/Chump`** with the full repo. Then configure as in the Chump repo’s setup docs (Ollama, `.env`, etc.).

**ChumpMenu:** Build from `~/Projects/Chump` with `./scripts/build-chump-menu.sh`. Default repo path is `~/Projects/Chump`; change in the menu only if your clone is elsewhere. **Log snapshot:** From Maclawd, `bash scripts/snapshot-chump-log.sh` writes the last 200 lines of chump.log to `chump-log-snapshot.txt` in the Maclawd root (Chump must have been run from `~/Projects/Chump` so logs exist).
