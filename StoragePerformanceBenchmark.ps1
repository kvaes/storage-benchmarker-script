Param( 
    [parameter(mandatory=$False,HelpMessage='Name of test file')] 
    [ValidateLength(2,30)] 
    $TestFileName = "StoragePerformance.test",

    [parameter(mandatory=$False,HelpMessage='What flavour do you want?')] 
    [ValidateSet('SQLIO','DISKSPD')] 
    $TestMethod = 'DISKSPD',

    [parameter(mandatory=$False,HelpMessage='Test file size in GB')] 
    [ValidateSet('1','5','10','50','100','500','1000')] 
    $TestFileSizeInGB = 100,

    [parameter(mandatory=$False,HelpMessage='Path to test folder')] 
    [ValidateLength(3,254)] 
    $TestFilepath = 'C:\Temp',

    [parameter(mandatory=$False,HelpMessage='Remove test file after benchmark')] 
    [ValidateSet('True','False')] 
    $TestFileRemove='True',

    [parameter(mandatory=$False,HelpMessage='Path to log folder')] 
    [ValidateLength(3,254)] 
    $TestLogDirectory=$TestFilePath+'\Logs',

    [parameter(mandatory=$False,HelpMessage='Enter the duration in seconds per test')] 
    [ValidateRange(10,1440)] 
    $TestDuration = '10',

    [parameter(mandatory=$False,HelpMessage='Enter the warmup in seconds per test')] 
    [ValidateRange(0,1440)] 
    $TestWarmup = '5',

    [parameter(mandatory=$False,HelpMessage='Name of the Test Scenario')] 
    [ValidateLength(1,254)] 
    $TestScenario='Default Test Scenario',

    [parameter(mandatory=$False,HelpMessage='Enter your API Key')] 
    [ValidateLength(16,32)] 
    $TestApiKey='UnregisteredTest',

    [parameter(mandatory=$False,HelpMessage='Do you want to share the benchmarks to improve the script')] 
    [ValidateSet('True','False')] 
    $TestShareBenchmarks='True',

    [parameter(mandatory=$False,HelpMessage='In a rush?')] 
    [ValidateSet('True','False')] 
    $QuickTest='True',

    [parameter(mandatory=$False,HelpMessage='Results only accesible via direct link')] 
    [ValidateSet('True','False')] 
    $Private='False',

    [parameter(mandatory=$False,HelpMessage='Want the link in your inbox?')] 
    [ValidateLength(1,254)] 
    $Email='False'
)

# Versioning
$Source = "https://bitbucket.org/kvaes/storage-performance-benchmarker"
$Version = 0.4
# PreFlight Variables
$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
$TestFileLocation = "$TestFilepath\$TestFileName"
$Folder = New-Item -Path $TestLogDirectory -ItemType Directory -Force -ErrorAction SilentlyContinue
$unixdate = (Get-Date -UFormat %s) -Replace("[,\.]\d*", "")
$endPoint = "http://storage.kvaes.be:80/api/send"

$systemname = (Get-WmiObject Win32_OperatingSystem).CSName
$operatingsystem = (Get-WmiObject Win32_OperatingSystem).Version
if ($Private) 
{
    $Prive = "1";
}
$ShareLink = "http://storage.kvaes.be/system/details/"+$systemname

# Functions
Function Share-URL{
    if ($TestShareBenchmarks -eq $True) {
            Write-Host "*"
            Write-Host "*** You can find a visualization of the results on ; $ShareLink"
            Write-Host "*"
    }
}

Function New-TestFile{
    $Folder = New-Item -Path $TestFilePath -ItemType Directory -Force -ErrorAction SilentlyContinue
    Write-Host "* Checking for $TestFileLocation"
    $FileExist = Test-Path $TestFileLocation
    if ($FileExist -eq $True)
    {
        if ($TestFileRemove -EQ 'True')
        {
            Remove-Item -Path $TestFileLocation -Force
        }
        else
        {
            Write-Host '* File Exists, break'
            Break
        }
    }
    Write-Host '* Creating test file using fsutil.exe...'
    & cmd.exe /c FSUTIL.EXE file createnew $TestFileLocation ($TestFileSizeInGB*1024*1024*1024)
    & cmd.exe /c FSUTIL.EXE file setvaliddata $TestFileLocation ($TestFileSizeInGB*1024*1024*1024)
}

Function Remove-TestFile{
    Write-Host "* Checking for $TestFileLocation"
    $FileExist = Test-Path $TestFileLocation
    if ($FileExist -eq $True)
    {
        Write-Host '* File Exists, deleting'
        Remove-Item -Path $TestFileLocation -Force
    }
}

Function StoragePerformanceBenchmark($TestName, $action, $Type,$KBytes,$oStart, $oStop, $threads){
    New-TestFile
    $request = ""
    Write-Host "*** Initialize for StoragePerformanceBenchmark $TestName"
    Write-Host "* Reading $KBytes Bytes in $Type mode using $TestFileLocation as target"
    $oStart..$oStop | % {
        $b = "-b$KBytes";
        $f = "-f$Type";
        $o = "-o $_";
        Write-Host "* $RunningFromFolder\sqlio.exe -s$TestDuration -k$action $f $b $o -t$threads -LS -BN $TestFileLocation"
        $Result = & $RunningFromFolder\sqlio.exe -s"$TestDuration" -k"$action" $f $b $o -t"$threads" -LS -BN "$TestFileLocation"
        Start-Sleep -Seconds 5 -Verbose
        $iops = $Result.Split("`n")[10].Split(':')[1].Trim() 
        $mbs = $Result.Split("`n")[11].Split(':')[1].Trim() 
        $latency = $Result.Split("`n")[14].Split(':')[1].Trim()
        $SeqRnd = $Result.Split("`n")[14].Split(':')[1].Trim()
        New-object psobject -property @{
            Type = $($Type)
            SizeIOKBytes = $($KBytes)
            OutStandingIOs = $($_)
            IOPS = $($iops)
            MBSec = $($mbs)
            LatencyMS = $($latency)
            Target = $("$TestFilePath\$TestFileName")
        }
        if ($TestShareBenchmarks -eq $True) {
            $request += @"
    <data>
      <MBSec>$mbs</MBSec>
      <IOPS>$iops</IOPS>
      <SizeIOKBytes>$KBytes</SizeIOKBytes>
      <LatencyMS>$latency</LatencyMS>
      <OutStandingIOs>$_</OutStandingIOs>
      <Type>$Type</Type>
      <Target>$TestFilePath\$TestFileName</Target>
      <Test>$TestName</Test>
    </data>
"@
        }
    }
    if ($TestShareBenchmarks -eq $True) {
        SendData($request)
    }
    Remove-TestFile
}

function Parse-DiskSPD {
    param ([String]$TestOutput)
    $Results = "" | Select MBSec, IOPS, Latency50, Latency75, Latency95, Latency99, LatencyMax, LatencyAvg
    $Results.IOPS       = Parse-Details -Path $TestOutput -Pattern "total:"
    $Results.MBSec      = Parse-Details -Path $TestOutput -Pattern "total:" -Index 2
    $Results.Latency50  = Parse-Details -Path $TestOutput -Pattern "50th"
    $Results.Latency75  = Parse-Details -Path $TestOutput -Pattern "75th"
    $Results.Latency95  = Parse-Details -Path $TestOutput -Pattern "95th"
    $Results.Latency99  = Parse-Details -Path $TestOutput -Pattern "99th"
    $Results.LatencyMax = Parse-Details -Path $TestOutput -Pattern "Max"
    $Results.LatencyAvg = Parse-Details -Path $TestOutput -Pattern "total:" -Index 4
    Return $Results
}

function Parse-Details {
    # Code "borrowed" from ; https://gallery.technet.microsoft.com/scriptcenter/Storage-Spaces-Performance-e6952a46 (credits where credits are due / MS-LPL License)
    param ([String]$path, [String]$pattern, [int]$index = 3)
    if (!(Test-Path -Path $path)) {
        $null
        return
    }
    $number = Select-String -Path $path -Pattern $pattern -SimpleMatch
    if ($number -ne $null) {
        $ret = [double]($number[0].Line.Split("|")[$index].Trim())
        $ret
    } else {
        -1
    }
}

Function StoragePerformanceBenchmarkDiskSpd($TestName, $action, $Type, $KBytes,$oStart, $oStop, $threadcount){
    New-TestFile
    $request = ""
    Write-Host "*** Initialize for StoragePerformanceBenchmark $TestName"
    Write-Host "* Testing $KBytes Bytes in $Type / $action mode using $TestFileLocation as target"
    $oStart..$oStop | % {
        $BlockSize = "-b" + $KBytes + "K";
        $Outstanding = "-o$_";
        switch($Type) {
            "sequential" { 
                $TypeParam = "";
            }
            "random" {
                $TypeParam = "-r$b";
            }
        }
        switch($action) {
            "R"  { $WritePerc = 0; }
            "W"  { $WritePerc = 100; }
            "rW" { $WritePerc = 70; }
            "Rw" { $WritePerc = 30; }
        }
        $Duration = "-d$TestDuration"
        $Warmup = "-W$TestWarmup"
        $Threads = "-t$threadcount"
        $Buffers = "-Z"
        $FileSize = "-c"+$TestFileSizeInGB+"G"
        $TestOutput = "$TestLogDirectory\$unixdate-$_-$action-$Type"
        $WritePerc = "-w"+$WritePerc

        Write-Host "* $RunningFromFolder\diskspd.exe $BlockSize $Duration $Warmup $Threads $Outstanding $TypeParam $WritePerc -h -L $Buffers $FileSize $TestFileLocation"
        $Result = & $RunningFromFolder\diskspd.exe $BlockSize $Duration $Warmup $Threads $Outstanding $TypeParam $WritePerc -h -L $Buffers $FileSize "$TestFileLocation" | Add-Content -Path $TestOutput
        Start-Sleep -Seconds 5 -Verbose
        $Parsed = Parse-DiskSPD -TestOutput $TestOutput
        New-object psobject -property @{
            Type = $($Type)
            SizeIOKBytes = $($KBytes)
            OutStandingIOs = $($_)
            IOPS = $($Parsed.IOPS)
            MBSec = $($Parsed.MBSec)
            LatencyMS = $($Parsed.LatencyAvg)
            Target = $("$TestFilePath\$TestFileName")
        }
        $mbs = $Parsed.MBSec
        $iops = $Parsed.IOPS
        $latency = $Parsed.LatencyAvg

        if ($TestShareBenchmarks -eq $True) {
            $request += @"
    <data>
      <MBSec>$mbs</MBSec>
      <IOPS>$iops</IOPS>
      <SizeIOKBytes>$KBytes</SizeIOKBytes>
      <LatencyMS>$latency</LatencyMS>
      <OutStandingIOs>$_</OutStandingIOs>
      <Type>$Type $action</Type>
      <Target>$TestFilePath\$TestFileName</Target>
      <Test>$TestName</Test>
    </data>
"@
        }
    }
    if ($TestShareBenchmarks -eq $True) {
        SendData($request)
    }
    Remove-TestFile
}

function SendData($reqBody) {
    try
    {
        Write-Host ("* Transmit customer improvement data "+$endPoint)
        $reqHeader = @"
<?xml version="1.0" encoding="utf-8"?>
<document>
    <system>
      <SystemName>$systemname</SystemName>
      <OperatingSystemVersion>$operatingsystem</OperatingSystemVersion>
      <ApiKey>$TestApiKey</ApiKey>
      <TestScenario>$TestScenario</TestScenario>
      <Date>$unixdate</Date>
      <Private>$prive</Private>
      <Email>$email</Email>
    </system>

"@
        $reqFooter = @"

</document>
"@
        $request = $reqHeader + $reqBody + $reqFooter
        $wr = [System.Net.HttpWebRequest]::Create($endPoint)
        $wr.Method= 'POST';
        $wr.ContentType="application/xml";
        $Body = [byte[]][char[]]$request;
        $wr.Timeout = 10000;
        $Stream = $wr.GetRequestStream();
        $Stream.Write($Body, 0, $Body.Length);
        $Stream.Flush();
        $Stream.Close();
        $resp = $wr.GetResponse().GetResponseStream()
        $sr = New-Object System.IO.StreamReader($resp) 
        $respTxt = $sr.ReadToEnd()
        Write-Host "* $($respTxt)";
    }
    catch
    {
        $errorStatus = "Exception Message: " + $_.Exception.Message;
        Write-Host "* $errorStatus";
    }
}

# Find out max cores of test system
function GetCPUinfo {
    param ([array]$servernames = ".")
    foreach ($servername in $servernames) {
        [array]$wmiinfo = Get-WmiObject Win32_Processor -computer $servername
        $cores = ( $wmiinfo | Select SocketDesignation | Measure-Object ).count
        $sockets = ( $wmiinfo | Select SocketDesignation -unique | Measure-Object ).count
        return $cores*$sockets;
    }
}
$MaxCores = GetCPUinfo


# Main Void
switch($TestMethod) {
    "DISKSPD" {
        Write-Host "***"
        Write-Host "*** Diskspeed is a 3th party tool which was included (x86fre version) in the distribution to make your life easier..."
        Write-Host "*** You can download DISKSPEED from ; https://gallery.technet.microsoft.com/DiskSpd-a-robust-storage-6cd2f223"
        Write-Host "*** Source code @ https://github.com/microsoft/diskspd"
        Write-Host "***"
        $TestFunction = 'StoragePerformanceBenchmarkDiskSpd'
        # DISKSPD fails (to write test file) without admin powers
        If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
        {   
            Write-Host "***"
            Write-Host "*** The script needs administrative rights to write the test file for diskspd"
            Write-Host "***"
            $arguments = "& '" + $myinvocation.mycommand.definition + "'"
            $testargs=@"
$arguments -QuickTest """$QuickTest""" -TestMethod """$TestMethod""" -TestFileSizeInGB """$TestFileSizeInGB""" -TestFilepath """$TestFilepath""" -TestFileRemove """$TestFileRemove""" -TestLogDirectory """$TestLogDirectory""" -TestDuration """$TestDuration""" -TestWarmup """$TestWarmup""" -TestScenario """$TestScenario""" -TestApiKey """$TestApiKey""" -TestShareBenchmarks """$TestShareBenchmarks""" -Private """$Private""" -Email """$Email"""
"@
            Start-Process "$psHome\powershell.exe" -PassThru -Verb runAs -ArgumentList @("$testargs")
            Share-URL
            Write-Host "*** Note : Be aware that the results will be available after the test run has completed!"
            exit       
        }
    }
    "SQLIO" {
        Write-Host "***"
        Write-Host "*** SQLIO is a 3th party tool which was included in the distribution to make your life easier..."
        Write-Host "*** You can download SQLIO from ; http://www.microsoft.com/en-us/download/details.aspx?id=20163"
        Write-Host "***"
        $TestFunction = 'StoragePerformanceBenchmarkDisk'
    }
}

$RunningFromFolder = $MyInvocation.MyCommand.Path | Split-Path -Parent 
Write-Host "***"
Write-Host “*** Running the Storage Performance Benchmark from $RunningFromFolder”
Write-Host “*** Using $TestFileLocation during the test for $TestDuration seconds"
Write-Host "*** This is version $Version, which can be obtained via $Source"
Write-Host "*** Logs can be found in $TestLogDirectory"
Write-Host "***"
Write-Host "*"
Write-Host "*** Available Parameters"
Write-Host "*" 
Write-Host "*   Parameter              Default Value           Information"
Write-Host "*   -----------------------------------------------------------------------------------------------------------" 
Write-Host "*   -QuickTest             True                    In a rush? One run per test with 16 outstanding I/O requests"
Write-Host "*   -TestMethod            DISKSPD                 What flavor do you want; DISKSPD or SQLIO?"
Write-Host "*   -TestFileSizeInGB      1                       Test file size in GB"
Write-Host "*   -TestFilepath          C:\Temp                 Path to test folder"
Write-Host "*   -TestFileRemove        True                    Remove test file after benchmark"
Write-Host "*   -TestLogDirectory      .\Logs                  Path to Log folder"
Write-Host "*   -TestDuration          10                      Duration of each individuel SQLIO/DISKSPD test"
Write-Host "*   -TestWarmup            5                       Warmup before each individuel DISKSPD test"
Write-Host "*   -TestScenario          Default                 Name of test scenario"
Write-Host "*   -TestApiKey            UnregisteredTest        API Key"
Write-Host "*   -TestShareBenchmarks   True                    Help us improve the script"
Write-Host "*   -Private               False                   Hide the results in the overview listing"
Write-Host "*   -Email                 *empty*                 Send the share link to an email (advised when doing -Private True)"
Write-Host "*"
Write-Host "*** Let's get ready to rumble!"
Write-Host "*"

if ($QuickTest -EQ 'True')
{
    Write-Host "* $TestFunction"
    Write-Host "*** Let's do a quick test!"
    Write-Host "*"
    . $TestFunction 'LargeIO - Read - Quick' 'R' 'sequential' '512' '16' '16' '1' | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-LargeIO-Read.csv"
    . $TestFunction 'SmallIO - Read - Quick' 'R' 'random' '8' '16' '16' $MaxCores | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-SmallIO-Read.csv"
    . $TestFunction 'LargeIO - Write - Quick' 'W' 'sequential' '512' '16' '16' '1' | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-LargeIO-Write.csv"
    . $TestFunction 'SmallIO - Write - Quick' 'W' 'random' '8' '16' '16' $MaxCores | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-SmallIO-Write.csv"
    if($TestMethod = "DISKSPD") {
        Write-Host "*"
        Write-Host "*** Extra Tests for DISKSPD"
        Write-Host "*"
        . $TestFunction 'LargeIO - Mixed 70% Write - Quick' 'rW' 'sequential' '512' '16' '16' '1'       | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-LargeIO-Mix70.csv"
        . $TestFunction 'SmallIO - Mixed 70% Write - Quick' 'rW' 'random'     '8'   '16' '16' $MaxCores | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-SmallIO-Mix70.csv"
        . $TestFunction 'LargeIO - Mixed 30% Write - Quick' 'Rw' 'sequential' '512' '16' '16' '1'       | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-LargeIO-Mix30.csv"
        . $TestFunction 'SmallIO - Mixed 30% Write - Quick' 'Rw' 'random'     '8'   '16' '16' $MaxCores | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-SmallIO-Mix30.csv"    
    }
}
else
{
    Write-Host "*** Let's do an extended test!"
    Write-Host "*"
    . $TestFunction 'LargeIO - Read - Extended' 'R' 'sequential' '512' '1' '32' '1' | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-LargeIO-Read.csv"
    . $TestFunction 'SmallIO - Read - Extended' 'R' 'random' '8' '8' '64' $MaxCores | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-SmallIO-Read.csv"
    . $TestFunction 'LargeIO - Write - Extended' 'W' 'sequential' '512' '1' '32' '1' | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-LargeIO-Write.csv"
    . $TestFunction 'SmallIO - Write - Extended' 'W' 'random' '8' '8' '64' $MaxCores | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-SmallIO-Write.csv"
    if($TestMethod = "DISKSPD") {
        Write-Host "*"
        Write-Host "*** Extra Tests for DISKSPD"
        Write-Host "*"
        . $TestFunction 'LargeIO - Mixed 70% Write - Extended' 'rW' 'sequential' '512' '1' '32' '1'       | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-LargeIO-Mix70.csv"
        . $TestFunction 'SmallIO - Mixed 70% Write - Extended' 'rW' 'random'     '8'   '8' '64' $MaxCores | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-SmallIO-Mix70.csv"
        . $TestFunction 'LargeIO - Mixed 30% Write - Extended' 'Rw' 'sequential' '512' '1' '32' '1'       | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-LargeIO-Mix30.csv"
        . $TestFunction 'SmallIO - Mixed 30% Write - Extended' 'Rw' 'random'     '8'   '8' '64' $MaxCores | Select-Object MBSec,IOPS,SizeIOKBytes,LatencyMS,OutStandingIOs,Type,Target | Export-Csv "$TestLogDirectory\$unixdate-StoragePerformanceBenchmark-SmallIO-Mix30.csv"    
    }
}

Write-Host "*"
Write-Host "*** Test finished in $($elapsed.Elapsed.ToString())"
Write-Host "*"

Share-URL

Write-Host "*"
Write-Host "*** Testing done : Press any key to continue ..."
Write-Host "*"
$HOST.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | OUT-NULL
$HOST.UI.RawUI.Flushinputbuffer()