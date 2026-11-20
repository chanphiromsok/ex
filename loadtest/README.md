# Load tests (Tsung)

Run from your Mac, never from the droplet. Needs `brew install tsung jq` and, once, `./patch-tsung.sh`
(Tsung 1.8.0 crashes on Erlang 27+ without it).

| File | What |
|---|---|
| `seed.sh` | Fills an empty server: prices, stations, routes, staff and supervisors. Writes `staff.csv`, `supervisors.csv` (git-ignored). |
| `ex.xml` | Normal day: ~10 → 60 → 180 users, think time 20–120 s. |
| `spike.xml` | Spike: normal, rush of 5 users/s, recovery, rush of 15 users/s, recovery. Needs `RATE_LIMIT=off`. |

## Run

```sh
# 1. Seed once, on an empty database
BASE=http://159.223.95.98 ADMIN_LOGIN=admin@gmail.com ADMIN_PASSWORD='...' ./seed.sh

# 2. Turn rate limits off (on the droplet), and redeploy
echo 'RATE_LIMIT=off' >> /etc/ex/uat.env && cd ~/ex/server && ./deploy/deploy.sh <tag>

# 3. Run (on the Mac); watch the droplet with: watch -n2 'docker stats --no-stream; free -m'
ulimit -n 10000
tsung -f spike.xml -l logs start

# 4. Status codes of the last run
grep -E '^stats: [0-9]{3} ' "logs/$(ls -t logs | head -1)/tsung.log" | awk '{c[$2]=$4} END {for (k in c) print k, c[k]}'
```

## After

- Remove `RATE_LIMIT=off` from `/etc/ex/uat.env` and redeploy. A CI deploy rewrites that file and removes it too.
- Run the `uat reset db` workflow: the test leaves thousands of shipments.
