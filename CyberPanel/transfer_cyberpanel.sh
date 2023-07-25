#!/bin/bash -x

# Plesk server details
plesk_host="IP_ADDR"
plesk_user="USER"
plesk_ftp_user="TEMP_FTP_USER"
plesk_ftp_password="TEMP_FTP_PASS"

phpVersion="8.1" # Cyberpanel only supports (as of 07/25/2023) v8.1 of PHP at the most. 
owner="admin" # Cyberpanel admin user
package="Default" # Cyberpanel package to use for every domain
email="EMAIL@DOMAIN.COM" # Email that is assigned to the domain created

tempDBPass="TEMPORARY DB PASSWORD NEEDS TO BE CHANGED MANUALLY" # Temporary database password

keyPem="./SSH_KEY.pem" # Plesk SSH key


# Output directory for downloaded files and databases
output_dir="/home/ubuntu/plesk" # Output directory for backup files from plesk

# Function to download files from Plesk server using FTP Note: this can take a while
download_files() {
    domain="$1"
    sudo ssh -i $keyPem "$plesk_user@$plesk_host" "sudo plesk bin ftpsubaccount --create $plesk_ftp_user -domain $domain -passwd $plesk_ftp_password -home /" 
    output_domain_dir="$output_dir/$domain"
    
    sudo mkdir -p "$output_domain_dir"
    echo "Downloading files for domain: $domain"

    ncftpget -u "$plesk_ftp_user" -p "$plesk_ftp_password" -R -V "$plesk_host" "$output_domain_dir" "/"

    echo "Downloading files for domain: $domain - COMPLETE"
    
    sudo ssh -i $keyPem "$plesk_user@$plesk_host" "sudo plesk bin ftpsubaccount --remove \"$plesk_ftp_user\" -domain \"$domain\""
}

# Function to download database from Plesk server
download_database() {

    domain="$1"
    db_name="$2"
    db_user="$3"
    
    echo "Downloading database $db_name for domain: $domain (DB user: $db_user)"


    output_db_file="$output_dir/$domain/$db_name.sql"

    sudo ssh -i "$keyPem" "$plesk_user@$plesk_host" "sudo plesk db dump $db_name > $db_name.sql && chown $plesk_user $db_name.sql"


    scp -i "$keyPem" "$plesk_user@$plesk_host:$db_name.sql" "$output_db_file"


    sudo cyberpanel createDatabase --databaseWebsite "$domain" --dbName "$db_name" --dbUsername "$db_user" --dbPassword "$tempDBPass"

    if mysql -u $db_user -p$tempDBPass $db_name < $output_db_file; then
        echo "$db_name for $domain successfully imported"
    else
        echo "$db_name for $domain could not be imported"
    fi
}

# Function to create CyberPanel account/domain
create_cyberpanel_account() {
    domain="$1"
    php="$2"
    owner="$3"
    package="$4"
    email="$5"

    echo "Creating CyberPanel account/domain for domain: $domain"

    # Create CyberPanel account

    sudo cyberpanel createWebsite --owner "$owner" --package "$package" --domainName "$domain" --email "$email" --php "$php"

    # Move files to CyberPanel domain directory
    cyberpanel_dir="/home/$domain"

    sudo cp -R "$output_domain_dir/httpdocs/." "$cyberpanel_dir/public_html/."

    echo "Created $domain successfully!"
    
}


# Main script

# Connect to the Plesk server and get the list of domains
domain_list=$(ssh -i "$keyPem" "$plesk_user@$plesk_host" "sudo plesk bin domain --list")


# Iterate over each domain
for domain in $domain_list; do

    # Download files from Plesk server
    download_files "$domain"

    # Create CyberPanel account/domain
    create_cyberpanel_account "$domain" "$phpVersion" "$owner" "$package" "$email"
    
    domain_db_list=$(ssh -i "$keyPem" "$plesk_user@$plesk_host" "sudo plesk db -N -e \"SELECT CONCAT_WS(',', db.name, IFNULL(dbu.login, 'NULL'), d.name) FROM data_bases db LEFT JOIN db_users dbu ON db.default_user_id = dbu.id LEFT JOIN domains d ON db.dom_id = d.id WHERE d.name IS NOT NULL AND d.name='$domain'\"")

    echo "Processing DB: $domain_db_list"

    # Loop through each line of the database response
    IFS=$'\n'
    for entry in $domain_db_list; do
        IFS=',' read -r db_name db_user db_domain <<< "$entry"
        if [ "$db_domain" = "$domain" ]; then
            # Domain has a matching database, so download it.
            echo "Found matching database: $db_name (user: $db_user)"
            download_database "$domain" "$db_name" "$db_user"
        fi
    done
done