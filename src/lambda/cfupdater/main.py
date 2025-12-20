import boto3
import urllib.request
import json
import os

def lambda_handler(event, context):
    sg_id = os.environ['SG_ID']
    port = 443
    
    ec2 = boto3.client('ec2')

    # Try downloading Cloudflare IPs
    try:
        with urllib.request.urlopen("https://api.cloudflare.com/client/v4/ips", timeout=5) as url:
            data = json.loads(url.read().decode())
            cf_ipv4 = data["result"]["ipv4_cidrs"]
            cf_ipv6 = data["result"]["ipv6_cidrs"]
    except Exception as e:
        print(f"[ERROR] Cannot reach Cloudflare API: {e}")
        return {
            "error": "cloudflare_api_unreachable",
            "details": str(e)
        }

    # Get current rules
    try:
        sg = ec2.describe_security_groups(GroupIds=[sg_id])["SecurityGroups"][0]
    except Exception as e:
        print(f"[ERROR] Cannot describe SG {sg_id}: {e}")
        return {
            "error": "sg_unreachable",
            "details": str(e)
        }

    current_ipv4 = []
    current_ipv6 = []

    for perm in sg.get("IpPermissions", []):
        if perm.get("FromPort") == port and perm.get("ToPort") == port and perm.get("IpProtocol") == "tcp":
            for cidr in perm.get("IpRanges", []):
                current_ipv4.append(cidr["CidrIp"])
            for cidr in perm.get("Ipv6Ranges", []):
                current_ipv6.append(cidr["CidrIpv6"])

    ipv4_to_add = list(set(cf_ipv4) - set(current_ipv4))
    ipv4_to_remove = list(set(current_ipv4) - set(cf_ipv4))

    ipv6_to_add = list(set(cf_ipv6) - set(current_ipv6))
    ipv6_to_remove = list(set(current_ipv6) - set(cf_ipv6))

    # Add new IPs
    if ipv4_to_add or ipv6_to_add:
        try:
            ec2.authorize_security_group_ingress(
                GroupId=sg_id,
                IpPermissions=[{
                    "IpProtocol": "tcp",
                    "FromPort": port,
                    "ToPort": port,
                    "IpRanges": [{"CidrIp": cidr, "Description": "Cloudflare Auto"} for cidr in ipv4_to_add],
                    "Ipv6Ranges": [{"CidrIpv6": cidr, "Description": "Cloudflare Auto"} for cidr in ipv6_to_add],
                }]
            )
        except Exception as e:
            print(f"[ERROR] Failed to authorize IPs: {e}")

    # Remove old IPs
    if ipv4_to_remove or ipv6_to_remove:
        try:
            ec2.revoke_security_group_ingress(
                GroupId=sg_id,
                IpPermissions=[{
                    "IpProtocol": "tcp",
                    "FromPort": port,
                    "ToPort": port,
                    "IpRanges": [{"CidrIp": cidr} for cidr in ipv4_to_remove],
                    "Ipv6Ranges": [{"CidrIpv6": cidr} for cidr in ipv6_to_remove],
                }]
            )
        except Exception as e:
            print(f"[ERROR] Failed to revoke IPs: {e}")

    return {
        "added_ipv4": ipv4_to_add,
        "removed_ipv4": ipv4_to_remove,
        "added_ipv6": ipv6_to_add,
        "removed_ipv6": ipv6_to_remove,
    }
