# Add Windows Firewall rules for Chator TURN server
# Run this script as Administrator!

Write-Host "Adding firewall rules for Chator Coturn..." -ForegroundColor Cyan

# Port 3478 - TURN/STUN control
netsh advfirewall firewall add rule name="Chator Coturn 3478 TCP" dir=in action=allow protocol=tcp localport=3478
netsh advfirewall firewall add rule name="Chator Coturn 3478 UDP" dir=in action=allow protocol=udp localport=3478

# Port 3479 - TURN/TLS
netsh advfirewall firewall add rule name="Chator Coturn 3479 TCP" dir=in action=allow protocol=tcp localport=3479
netsh advfirewall firewall add rule name="Chator Coturn 3479 UDP" dir=in action=allow protocol=udp localport=3479

# Relay port range (49160-49200)
netsh advfirewall firewall add rule name="Chator Coturn Relay TCP" dir=in action=allow protocol=tcp localport=49160-49200
netsh advfirewall firewall add rule name="Chator Coturn Relay UDP" dir=in action=allow protocol=udp localport=49160-49200

Write-Host "Done! Verifying..." -ForegroundColor Cyan
netsh advfirewall firewall show rule name=all 2>&1 | findstr "Chator"
