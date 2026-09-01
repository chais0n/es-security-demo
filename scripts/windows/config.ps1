######################
## EXFIL VARIABLES  ##
######################
# NOTE: Keep these in sync with the EXFILL_* values in scripts/.env

# The Ubuntu host that exfil data will be SCP'd to
$ExfilTarget = '34.70.48.90'

# The SSH user on the Ubuntu exfil host
$ExfilUser = 'bad_lady'

# Path to the SSH private key ON THIS WINDOWS HOST used to connect to ExfilTarget
# (OpenSSH key format; generate with ssh-keygen on the Windows host)
$ExfilKeyPath = 'C:\Users\bad_guy\.ssh\cgrfn-gcp-deb'

# The compressed archive that will be staged and exfiltrated
$ExfilFile = "$env:TEMP\totally_not_exfil_win.zip"
