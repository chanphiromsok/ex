# Test deploy on one $4 DigitalOcean droplet (app + Postgres)

For solo testing only: HTTP on the droplet IP, no domain, no HTTPS, Postgres on the same machine.
Droplet: Ubuntu 24.04, 512 MB RAM (add swap below or the build will be killed).

## 1. Swap, packages, Postgres (as root)

```sh
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

apt-get update
apt-get install -y git curl build-essential autoconf m4 libssl-dev libncurses-dev unzip postgresql

# Postgres, localhost only, small footprint
sudo -u postgres psql -c "CREATE USER ex WITH PASSWORD 'CHANGE_ME_DB_PASSWORD';"
sudo -u postgres psql -c "CREATE DATABASE ex OWNER ex;"
sed -i "s/^#\?shared_buffers.*/shared_buffers = 32MB/" /etc/postgresql/*/main/postgresql.conf
systemctl restart postgresql
```

## 2. Build the release (as root, takes a while on 512 MB)

Versions come from the `Dockerfile` (Elixir 1.20.5, OTP 29.1.2); `mise` installs both.

```sh
curl https://mise.run | sh && export PATH="$HOME/.local/bin:$PATH"
mise use -g erlang@29.1.2 elixir@1.20.5-otp-29

git clone https://github.com/chanphiromsok/ex.git /opt/ex-src && cd /opt/ex-src
git checkout release/1.0.0
cd server
export MIX_ENV=prod
mix local.hex --force && mix local.rebar --force
mix deps.get --only prod
mix assets.setup && mix assets.deploy   # skip if mix reports no such task
mix release --overwrite
cp -r _build/prod/rel/ex /opt/ex
```

## 3. Configuration

```sh
cat > /etc/ex.env <<EOF
PHX_SERVER=true
PHX_HOST=$(curl -s ifconfig.me)
PORT=80
DATABASE_URL=ecto://ex:CHANGE_ME_DB_PASSWORD@localhost/ex
POOL_SIZE=3
RELEASE_MODE=interactive
ERL_FLAGS=+MBas aobf +MHas aobf +MMmcs 0
SECRET_KEY_BASE=$(cd /opt/ex-src/server && mix phx.gen.secret)
TOKEN_SIGNING_SECRET=$(cd /opt/ex-src/server && mix phx.gen.secret)
SEED_ADMIN_EMAIL=admin@example.com
SEED_ADMIN_PASSWORD=CHANGE_ME_ADMIN_PASSWORD
EOF
chmod 600 /etc/ex.env
```

Edit the three `CHANGE_ME` values before continuing.

## 4. Migrate, seed, run

```sh
set -a; . /etc/ex.env; set +a
/opt/ex/bin/ex eval Ex.Release.migrate
/opt/ex/bin/ex eval Ex.Release.seed

cat > /etc/systemd/system/ex.service <<'EOF'
[Unit]
Description=Express goods API
After=network.target postgresql.service

[Service]
EnvironmentFile=/etc/ex.env
ExecStart=/opt/ex/bin/ex start
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now ex
```

Check it: `curl http://<droplet-ip>/api/v1/open_api` should return JSON.
Firewall: allow only 22 and 80 (`ufw allow 22 && ufw allow 80 && ufw enable`); Postgres stays on localhost.

## Updating later

```sh
cd /opt/ex-src && git pull && cd server && MIX_ENV=prod mix release --overwrite
systemctl stop ex && rm -rf /opt/ex && cp -r _build/prod/rel/ex /opt/ex
set -a; . /etc/ex.env; set +a; /opt/ex/bin/ex eval Ex.Release.migrate
systemctl start ex
```

## Notes

- The seed admin defaults to `admin@gmail.com` / `12345678` if the `SEED_*` variables are unset; always set them on a public IP.
- If the build is killed (out of memory), resize the droplet to 1 GB for the build, then resize back, or build locally and copy `server/_build/prod/rel/ex` over (same OS and architecture needed).
- Memory: `RELEASE_MODE=interactive` loads code on first use. In a local Docker test it took the app from about 440 MB to about 150-170 MB; the allocator flags in `ERL_FLAGS` gave a smaller saving. Scheduler count is left at the default.
- Not verified: written from the repo's config, not run on a real droplet.
