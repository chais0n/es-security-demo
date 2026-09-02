######################
## EXFIL VARIABLES  ##
######################
# NOTE: Keep these in sync with the EXFILL_* values in scripts/.env

# The Ubuntu host that exfil data will be SCP'd to
$ExfilTarget = ''

# The SSH user on the Ubuntu exfil host
$ExfilUser = ''

# Path to the SSH private key ON THIS WINDOWS HOST used to connect to ExfilTarget
$ExfilKeyPath = ''
