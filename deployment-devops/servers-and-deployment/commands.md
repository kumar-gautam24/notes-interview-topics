# Command cheat-sheet (the "come back to it" file)

The other four files are for *learning*; this one is for *remembering*. Once the concepts click, you
won't want to re-read prose to recall a flag — you'll want the command in one line. That's this file.

🎓 A tip on how to use it: don't try to memorize any of this. Understand *why* each command exists
(that's what the other files are for), and this becomes a place your eyes land on to jog your memory,
not something you study. Every command here is one we actually ran.

`[LOCAL]` = your Mac · `[SERVER]` = inside the SSH session.

---

## SSH & keys `[LOCAL]`
```bash
chmod 400 ~/Downloads/recurring-key.pem            # SSH refuses keys others can read
ssh -i ~/Downloads/recurring-key.pem ubuntu@203.0.113.10   # connect
#   -i <keyfile>   which private key to use
#   ubuntu@        the default user on Ubuntu AMIs
exit                                                # leave the server
```
Copy a file to the server (not used here, but the sibling of ssh):
```bash
scp -i ~/Downloads/recurring-key.pem localfile ubuntu@203.0.113.10:/home/ubuntu/
```

## System & packages (apt) `[SERVER]`
```bash
sudo apt update                 # refresh the list of available packages
sudo apt install -y nginx       # install a package (-y = don't prompt)
sudo apt clean                  # delete downloaded .deb cache (frees space)
sudo apt --fix-broken install   # finish a half-completed/interrupted install
```

## Swap (overflow RAM) `[SERVER]`
```bash
sudo fallocate -l 2G /swapfile              # make a 2 GB file
sudo chmod 600 /swapfile                    # only root can read/write it
sudo mkswap /swapfile                       # format it as swap
sudo swapon /swapfile                       # activate it
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab   # survive reboots
free -h                                      # show RAM + swap
```

## Disk `[SERVER]`
```bash
df -h /                                       # how full is the root filesystem (Use%)
du -sh ~/honest-ledger                        # size of one folder
sudo du -h -d1 / 2>/dev/null | sort -hr | head   # biggest top-level folders — "why is my disk full"
lsblk                                          # block devices: disks & partitions & sizes
sudo growpart /dev/nvme0n1 1                   # grow partition 1 into the enlarged disk
sudo resize2fs /dev/nvme0n1p1                  # grow the ext4 filesystem into the partition
```

## Docker `[SERVER]`
```bash
curl -fsSL https://get.docker.com | sudo sh    # install Docker (official script)
sudo usermod -aG docker $USER                  # run docker without sudo (re-login after)
docker --version && docker compose version     # sanity check
docker compose up -d --build                   # build + start in background
docker compose ps                              # status of the services
docker compose logs -f api                     # follow live app logs (Ctrl-C to stop watching)
docker compose exec api bash                   # shell inside the running container
docker system df                               # Docker's disk usage
docker builder prune -f                        # delete build cache (safe)
```
(Full Docker reference: [docker.md](docker.md).)

## Git `[SERVER]` / `[LOCAL]`
```bash
git clone https://github.com/kumar-gautam24/honest-ledger.git   # [SERVER] get the code
git pull                                                        # [SERVER] fetch latest to deploy
# [LOCAL] the other half of the loop:
git add -A && git commit -m "..." && git push
```

## The app's `.env` `[SERVER]`
```bash
cp .env.example .env
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(openssl rand -hex 32)|" .env  # real random secret
sed -i "s|^ENV=.*|ENV=production|" .env
grep -E '^(ENV|JWT_SECRET)=' .env                                   # verify
#   sed -i "s|old|new|"  = edit the file in place, replacing a pattern
#   openssl rand -hex 32 = 32 random bytes as hex (a strong secret)
```

## Nginx `[SERVER]`
```bash
sudo tee /etc/nginx/sites-available/recurring > /dev/null <<'EOF'
...config...
EOF                                            # write a root-owned config file
sudo ln -s /etc/nginx/sites-available/recurring /etc/nginx/sites-enabled/   # enable site
sudo rm /etc/nginx/sites-enabled/default       # disable the default site
sudo nginx -t                                  # TEST config before applying (always!)
sudo systemctl reload nginx                    # apply, zero downtime
sudo systemctl status nginx                    # is it running?
```

## Certbot / HTTPS `[SERVER]`
```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d 203-0-113-10.nip.io    # get + install a cert, edit Nginx
systemctl list-timers | grep certbot           # confirm auto-renew is armed
sudo certbot renew --dry-run                    # test renewal without using rate limits
```

## Health checks `[LOCAL or SERVER]`
```bash
curl http://localhost:8000/health              # [SERVER] liveness (process up)
curl http://localhost:8000/ready               # [SERVER] readiness (DB reachable)
curl -i http://203-0-113-10.nip.io/health      # -i shows status code + headers
curl --max-time 5 http://203.0.113.10:8000/health   # demo: times out (port 8000 firewalled)
```

---

## Flag glossary (the little letters)
| Flag | Means |
|------|-------|
| `-i` (ssh) | **i**dentity file (the key) |
| `-i` (curl) | **i**nclude response headers |
| `-d` (docker) | **d**etached (background) |
| `-f` (curl) | **f**ail silently on errors |
| `-f` (logs / prune) | **f**ollow / **f**orce |
| `-h` (df/du/free) | **h**uman-readable sizes |
| `-y` (apt) | assume **y**es to prompts |
| `-s` (ln) | **s**ymbolic link |
| `-r` (sort) | **r**everse (biggest first) |
| `-l` (fallocate) | **l**ength (size) |
