# -like patterns matched against a computer's operatingSystem attribute.
# 'Windows Server*2008*' also covers 'Windows Server(R) 2008' (trademark symbol).
$script:EolOperatingSystemPatterns = @(
    'Windows XP*'
    'Windows Vista*'
    'Windows 7*'
    'Windows 8*'
    'Windows Server*2003*'
    'Windows Server*2008*'
    'Windows Server*2012*'
)
