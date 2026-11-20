FROM kalilinux/kali-rolling

RUN apt-get update && apt-get install -y --no-install-recommends \
    nmap \
    netcat-openbsd \
    curl \
    iproute2 \
    iputils-ping \
    git \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# AutoBlue-MS17-010: zzz_exploit.py + mysmb.py + requirements
RUN git clone --depth 1 https://github.com/3ndG4me/AutoBlue-MS17-010.git /opt/AutoBlue-MS17-010 \
    && pip3 install --no-cache-dir --break-system-packages -r /opt/AutoBlue-MS17-010/requirements.txt

WORKDIR /opt/AutoBlue-MS17-010