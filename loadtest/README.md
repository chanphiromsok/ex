# Load tests (Tsung)

Run from your Mac, never from the droplet. Needs `brew install tsung jq` and, once, `./patch-tsung.sh`
(Tsung 1.8.0 crashes on Erlang 27+ without it).

| File | What |
|---|---|
| `seed.sh` | Fills an empty server: prices, stations, routes, staff and supervisors. Writes `staff.csv`, `supervisors.csv` (git-ignored). |
| `ex.xml` | Normal day: ~10 → 60 → 180 users, think time 20–120 s. |
| `spike.xml` | Realistic rush: 40 staff (10 branches × 4) sign in once, then shipments go from one every 2–3 min to one every 5–10 s per person, and back. ~18 min. Seed with `STATIONS=10 STAFF=4`. Needs `RATE_LIMIT=off`. |
| `flood.xml` | Stress: waves of NEW users signing in (up to 15/s). Mostly measures password hashing; it froze the 1 GB droplet. Needs `RATE_LIMIT=off`. |

`RATE_LIMIT=off` is needed only because every simulated branch comes from this one Mac IP.

## Run

```sh
# 1. Seed once, on an empty database
BASE=http://159.223.95.98 ADMIN_LOGIN=admin@gmail.com ADMIN_PASSWORD='...' STATIONS=10 STAFF=4 ./seed.sh

# 2. Turn rate limits off (on the droplet), and redeploy
echo 'RATE_LIMIT=off' >> /etc/ex/uat.env && cd ~/ex/server && ./deploy/deploy.sh <tag>

# 3. Run (on the Mac); watch the droplet with: watch -n2 'docker stats --no-stream; free -m'
ulimit -n 10000
tsung -f spike.xml -l logs start

# 4. Optional, during the run (on the droplet): where scheduler time goes for 10 s
docker exec ex-app-1 /app/bin/ex rpc ':msacc.start(10_000); :msacc.print()'

# 5. Status codes of the last run
grep -E '^stats: [0-9]{3} ' "logs/$(ls -t logs | head -1)/tsung.log" | awk '{c[$2]=$4} END {for (k in c) print k, c[k]}'
```

## After

- Remove `RATE_LIMIT=off` from `/etc/ex/uat.env` and redeploy. A CI deploy rewrites that file and removes it too.
- Run the `uat reset db` workflow: the test leaves thousands of shipments.

## HTML report

Needs `gnuplot` and the Perl `Template` module (`cpanm -l ~/perl5 Template`, then `export PERL5LIB=~/perl5/lib/perl5`).

```sh
cd "logs/$(ls -t logs | head -1)" && "$(brew --prefix tsung)/lib/tsung/bin/tsung_stats.pl" && open graph.html
```
