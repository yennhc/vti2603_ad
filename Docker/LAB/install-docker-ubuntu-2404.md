The recommended way to install Docker on **Ubuntu 24.04 LTS** is from Docker's official repository, which provides the latest stable version of Docker Engine and Docker Compose.

### 1. Remove old versions (if any)

```bash
sudo apt-get remove docker docker-engine docker.io containerd runc
```

---

### 2. Update packages

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release
```

---

### 3. Add Docker's official GPG key

```bash
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

---

### 4. Add the Docker repository

```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

---

### 5. Install Docker Engine and Docker Compose

```bash
sudo apt update

sudo apt install -y docker-ce docker-ce-cli containerd.io \
docker-buildx-plugin docker-compose-plugin
```

---

### 6. Verify the installation

Check Docker:

```bash
docker --version
```

Example output:

```text
Docker version 28.x.x
```

Check Docker Compose:

```bash
docker compose version
```

Example output:

```text
Docker Compose version v2.x.x
```

> **Note:** Modern Docker uses **`docker compose`** (with a space), not the older `docker-compose` command.

---

### 7. Allow your user to run Docker without `sudo`

```bash
sudo usermod -aG docker $USER
```

Then either:

```bash
newgrp docker
```

or log out and log back in.

Test:

```bash
docker run hello-world
```

You should see a message indicating Docker is working correctly.

---

### 8. Enable Docker at boot

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

Check status:

```bash
sudo systemctl status docker
```

---

## Quick verification

```bash
docker --version
docker compose version
docker run hello-world
```

If all three commands succeed, Docker and Docker Compose are installed correctly on Ubuntu 24.04.