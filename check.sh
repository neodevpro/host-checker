#!/bin/bash

# Check if the domain can be resolved and accessed
check_domain() {
    domain=$1
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    ip=""
    http_status=1
    https_status=1

    # Try to resolve the domain (using dig and getent)
    resolve_domain() {
        ip=$(dig +short "$domain" || true)  # Use dig, ensure it doesn't stop the script even if it fails
        if [[ -z "$ip" ]]; then
            ip=$(getent hosts "$domain" | awk '{print $1}' || true)  # Fallback to getent
        fi
        if [[ -z "$ip" ]]; then
            ip=$(nslookup "$domain" | grep 'Address' | tail -n 1 | awk '{print $2}' || true)  # Fallback to nslookup
        fi
    }

    # Check HTTP and HTTPS if the domain resolution fails
    check_http_https() {
        # Only check HTTP and HTTPS if the domain couldn't be resolved
        if [[ -z "$ip" ]]; then
            # Run HTTP and HTTPS checks concurrently with a 2-second timeout
            http_status=$(curl --connect-timeout 2 -s -o /dev/null -w "%{http_code}" "http://$domain" | grep -q '200' && echo 0 || echo 1)
            https_status=$(curl --connect-timeout 2 -s -o /dev/null -w "%{http_code}" "https://$domain" | grep -q '200' && echo 0 || echo 1)
        fi
    }

    # Run domain resolution and HTTP/HTTPS checks concurrently
    resolve_domain &
    check_http_https &

    # Wait for the concurrent tasks to finish
    wait

    # If the domain was resolved successfully, log the result
    if [[ -n "$ip" ]]; then
        echo "$timestamp - $domain resolved successfully, IP: $ip"
    fi

    # If the domain could not be resolved and HTTP/HTTPS are both inaccessible, log it to deadfile.log
    if [[ -z "$ip" && $http_status -eq 1 && $https_status -eq 1 ]]; then
        echo "$timestamp - $domain cannot be resolved or accessed"
        echo $domain >> deadfile
    fi
}

export -f check_domain

# Clear old files to avoid duplicate logs
> deadfile
> deadfile.log

# Use parallel to run the check_domain function concurrently with 128 threads
# Read the domain list from an input file, assuming 'block' contains the list of domains
cat block | parallel -j 128 check_domain
