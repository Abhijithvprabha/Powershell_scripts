# Set rules for ICMP (Allow Ping)
New-NetFirewallRule -DisplayName "Inbound ICMPv4" -Direction Inbound -Protocol ICMPv4 -Action Allow -Profile Any -Enabled True
New-NetFirewallRule -DisplayName "Outbound ICMPv4" -Direction Outbound -Protocol ICMPv4 -Action Allow -Profile Any -Enabled True
