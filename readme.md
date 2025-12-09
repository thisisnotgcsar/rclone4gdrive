```
          _                     ___           _      _           
         | |                   /   |         | |    (_)          
 _ __ ___| | ___  _ __   ___  / /| | __ _  __| |_ __ ___   _____ 
| '__/ __| |/ _ \| '_ \ / _ \/ /_| |/ _` |/ _` | '__| \ \ / / _ \
| | | (__| | (_) | | | |  __/\___  | (_| | (_| | |  | |\ V /  __/
|_|  \___|_|\___/|_| |_|\___|    |_/\__, |\__,_|_|  |_| \_/ \___|
                                     __/ |                       
                                    |___/                        
```

[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc-sa/4.0/)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/thisisnotgcsar/rclone4gdrive/releases)
[![Build Status](https://img.shields.io/badge/build-manual-lightgrey.svg)](https://github.com/thisisnotgcsar/rclone4gdrive/actions)

# rclone4gdrive <!-- omit in toc -->

Seamless, automated, and transparent two-way Google Drive backup for Linux.

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Directory Structure](#directory-structure)
- [How rclone4gdrive works](#how-rclone4gdrive-works)
- [Customization](#customization)
- [Contributing](#contributing)
- [Acknowledgements](#acknowledgements)
- [Meta](#meta)

## Overview

rclone4gdrive is a rclone wrapper for Google Drive two-way synchronization. This is typically used for Cloud backup purposes.

Your `~/gdrive/` directory acts as a real-time view of your Google Drive root directory. Any files you add, modify, or delete in `~/gdrive/` are transparently synchronized to Google Drive, and changes made on Google Drive are automatically synced back to your local directory. 

rclone4gdrive automates common rclone operations and error handling to give the user a "set-up and forget" experience for filesystem-aware cloud backup. It solves a very boring but important issue in the Linux open-source cloud backup space: setting up and automating a seamless and transparent cloud backup of files directly from the Linux filesystem, with minimal manual intervention.

## Features
- One-command setup for rclone remote and local sync directory
- Installs and manages systemd user units for scheduled syncs
- Automated detection and handling of rclone failures (token expiry, resync required, etc.)
- Automatic OAuth token refresh and config update
- Dry-run and status commands for safe testing and monitoring
- Ignores all Google Office Suite files during backup to avoid issues with the Linux filesystem
- All scripts are POSIX shell compatible (no Bash required)

## Installation
1. Ensure you have rclone, systemd (user mode), and jq installed:
	 - **rclone**: The core tool for synchronizing files with Google Drive. rclone4gdrive wraps and automates rclone operations. [Install instructions](https://rclone.org/install/) or run:
		 ```sh
		 curl https://rclone.org/install.sh | sudo bash
		 ```
	 - **systemd (user mode)**: Used to schedule and manage sync operations automatically. Most modern Linux distributions include systemd. To enable user mode:
		 ```sh
		 loginctl enable-linger $USER
		 # Log out and back in for changes to take effect
		 ```
	 - **jq**: Required for parsing and manipulating JSON data. This is used for handling OAuth tokens and updating rclone configuration files.
		 Install with your package manager, e.g.:
		 ```sh
		 sudo apt-get install jq   # Debian/Ubuntu
		 sudo dnf install jq       # Fedora
		 sudo pacman -S jq        # Arch
		 ```
2. You should also have set up **Google Cloud Console personal OAuth API credentials**. These credentials are required because rclone4gdrive uses them to securely access your Google Drive account via the Google Drive API. Without them, rclone cannot authenticate or perform sync operations on your behalf. If you don't have them set up, here's how to do it:
	1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
	2. Create a new project (or select an existing one).
	3. Navigate to **APIs & Services > Credentials**.
	4. Click **Create Credentials > OAuth client ID**.
	5. If prompted, configure the consent screen (fill in required fields).
	6. Choose **Desktop app** as the application type.
	7. Name your client and click **Create**.
	8. Download the credentials JSON file, or copy the **Client ID** and **Client Secret**.
	9. When configuring rclone, use these credentials for your Google Drive remote (you can specify them during initialization).
3. Clone this repository to your system.
4. Run the initialization command:
	```sh
	./rclone4gdrive init
	```
	This will:
   - Copy this repository directory to `~/bin/rclone4gdrive`
   - Add `~/bin/rclone4gdrive` to your PATH (via `~/.bashrc`)
   - Set up the rclone remote (named `gdrive`)
   - Install and enable the systemd user units for scheduled sync and failure handling

	Once installation is complete, rclone4gdrive will start its execution and begin backing up and downloading files from Google Drive into your `$HOME/gdrive/` directory.

## Usage
> Your `~/gdrive/` directory is effectively a real-time view of your Google Drive root directory. Everything inserted, modified, or deleted within `~/gdrive/` will be transparently synchronized to your configured Google Drive location. This works both ways—changes made on Google Drive will also sync back to your local `~/gdrive/` directory.

After installation, you can use the following commands:
```sh
rclone4gdrive status        # Show sync and service status 
rclone4gdrive restart       # Restart the timer and service 
rclone4gdrive dry-run       # Test sync without making changes
rclone4gdrive sync-daemons  # Reinstall and enable systemd units
rclone4gdrive init          # (Re)initialize everything
```


## Directory Structure
- `rclone4gdrive`           : Main script/entrypoint
- `refresh_token.sh`        : Script to refresh OAuth token and update `rclone.conf`
- `rclone-fail-handler.sh`  : Handles sync failures and triggers recovery
- `daemons/`                : systemd user unit files
	- `rclone.service`         : Runs the rclone bisync operation
	- `rclone.timer`           : Schedules regular syncs
	- `rclone-fail.service`    : Handles failures and triggers recovery actions

## How rclone4gdrive works

The rclone4gdrive system automates two-way synchronization between your local `$HOME/gdrive/` directory and Google Drive, using rclone and systemd for reliability and hands-off operation.

At its core, rclone4gdrive leverages systemd user services and timers to schedule and execute **rclone bisync operations** at regular intervals. This oepration which performa safe, two-way synchronization—detecting changes, additions, and deletions on both sides and propagating them so that your local and Google Drive folders always match. 

The **timer service** triggers the **sync service**, which runs rclone in bisync mode to ensure both local and remote directories are kept in sync. All operations are atomic and logged to the systemd journal for monitoring.

Robust error handling is built in: if a sync fails (e.g., due to an expired OAuth token or a required resync), a dedicated failure handler is triggered: `rclone-fail-handler.sh`. This handler inspects recent logs, detects known error patterns, and attempts automated recovery steps such as refreshing the OAuth token or running a resync. If recovery succeeds, the timer and service are restarted automatically; otherwise, the user is notified for manual intervention.

OAuth token management is fully automated. The refresh script (`refresh_toke.sh`) extracts credentials from your rclone configuration, requests a new access token from Google, and updates the config file safely, with backup and rollback in case of errors. Token validity is verified by running a dry-run sync before finalizing changes.

All scripts are written in Bash for portability. JSON parsing and manipulation are handled with jq. The system is designed to ignore Google Docs files during backup, preventing issues with the Linux filesystem. All configuration and logs are stored in user directories, requiring no root access and keeping your environment clean and secure.

## Customization
- Edit the systemd unit files in `daemons/` to change sync frequency or behavior

## Contributing
Pull requests and issues are welcome! Please open an issue for bugs or feature requests.

## Acknowledgements
rclone4gdrive relies on the following third-party tools and services:
- **rclone**: For robust cloud file synchronization and bisync operations ([rclone.org](https://rclone.org/))
- **jq**: For parsing and manipulating JSON data in shell scripts ([stedolan.github.io/jq/](https://stedolan.github.io/jq/))
- **Google Drive**: As the cloud storage backend, accessed via the Google Drive API ([google.com/drive/](https://www.google.com/drive/))

## Meta
gcsar

<p xmlns:cc="http://creativecommons.org/ns#" xmlns:dct="http://purl.org/dc/terms/"><a property="dct:title" rel="cc:attributionURL" href="https://github.com/thisisnotgcsar/rclone4gdrive">rclone4gcsar</a> by <a rel="cc:attributionURL dct:creator" property="cc:attributionName" href="https://github.com/thisisnotgcsar">gcsar</a> is licensed under <a href="http://creativecommons.org/licenses/by-nc-sa/4.0/?ref=chooser-v1" target="_blank" rel="license noopener noreferrer" style="display:inline-block;">CC BY-NC-SA 4.0<img style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/cc.svg?ref=chooser-v1"><img style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/by.svg?ref=chooser-v1"><img style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/nc.svg?ref=chooser-v1"><img style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/sa.svg?ref=chooser-v1"></a></p>

https://github.com/thisisnotgcsar