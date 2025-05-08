Cloudflare API version4 Dynamic DNS Update in Bash, without unnecessary requests.

Now the script also supports IPv6(AAAA DDNS Recoards) or both IPv4 and IPv6.

Add support for Account owned tokens(see https://dash.cloudflare.com/profile/api-tokens).

Installation:
```bash
curl https://raw.githubusercontent.com/meepuru/cloudflare-api-v4-ddns-fix/master/cf-v4-ddns.sh > /usr/local/bin/cf-ddns.sh && chmod +x /usr/local/bin/cf-ddns.sh
```

then edit the script and set your Cloudflare API token, zone id, domain name and record name.

or you can use the following command to set them:
```bash
cf-ddns.sh -t <your_token> -z <your_zone_id> -d <your_domain_name> -r <your_record_name>
```

run `cf-ddns.sh -?` for full usage.

Automatically run the script every minute using cron:

run `crontab -e` and add next line:
```bash
*/1 * * * * /usr/local/bin/cf-ddns.sh >/dev/null 2>&1
```

or you need log:
```bash
*/1 * * * * /usr/local/bin/cf-ddns.sh >> /var/log/cf-ddns.log 2>&1
```