# Plesk to CyberPanel Migration Script

This script is used to migrate websites from a Plesk server to a CyberPanel server. It connects to the Plesk server, downloads the files and databases of each domain, and then creates the corresponding account and domain in CyberPanel.

## Requirements
- Plesk server details (IP address, username)
- Temporary FTP user and password for accessing Plesk files
- PHP version supported by CyberPanel (currently v8.1)
- Owner, package, and email details for creating CyberPanel account/domain
- Temporary database password for creating databases in CyberPanel
- SSH key for connecting to the Plesk server

## Usage
- Set the Plesk server details, FTP user details, PHP version, owner, package, email, temporary database password, and SSH key in the script.
- Set the output directory where downloaded files and databases will be stored.
- Run the script using the command: bash transfer_cyberpanel.sh 

# Functions
`download_files():` This function downloads the files from the Plesk server using FTP.
Parameters: $domain - the domain for which files should be downloaded.
It creates a temporary FTP subaccount, downloads the files using ncftpget, and then removes the subaccount.

`download_database():` This function downloads the database from the Plesk server and imports it into CyberPanel.
Parameters: $domain - the domain for which the database should be downloaded.
It dumps the database from Plesk, copies the dump file to the output directory, creates a new database in CyberPanel, and imports the dump file into the new database.

`create_cyberpanel_account():` This function creates a new CyberPanel account/domain for the given domain.
Parameters: $domain - the domain for which the CyberPanel account/domain should be created. $php - the PHP version to be used for the domain. $owner - the owner of the CyberPanel account/domain. $package - the package to be used for the CyberPanel account/domain. $email - the email assigned to the domain.
It creates a new CyberPanel account/domain using the provided details and moves the files from the Plesk server to the CyberPanel domain directory.

## Main Script
- The script connects to the Plesk server and retrieves the list of domains.
- It iterates over each domain and performs the following steps:
- Downloads files from the Plesk server using the download_files() function.
- Creates a new CyberPanel account/domain using the create_cyberpanel_account() function.
- Retrieves the list of databases for the domain from the Plesk server.
- For each matching database, downloads it using the download_database() function.