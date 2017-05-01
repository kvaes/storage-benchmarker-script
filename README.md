Author
======
* Karim Vaes
* http://www.kvaes.be

Origin
======
* http://storage.kvaes.be/

Requirements
============
Powershell version 4 or upwards need to be installed.
If you want to run this on (for instance) Windows 2008, please check the [following documentation](https://social.technet.microsoft.com/wiki/contents/articles/20623.step-by-step-upgrading-the-powershell-version-4-on-2008-r2.aspx)

Parameters Information
======================

Information | Parameter | Default Value
----------- | --------- | -------------
In a rush? One run per test | -QuickTest | False
What flavor do you want? | -TestMethod | DISKSPD
Name of test file | -TestFileName | StoragePerformance.test
Test file size in GB | -TestFileSizeInGB  | 1
Path to test folder | -TestFilepath | C:\Temp
Remove test file after benchmark | -TestFileRemove | True
Path to log folder | -TestLogDirectory | .\Logs
Enter the duration in seconds per test | -TestDuration | 10
Warmup before each individual DISKSPD test | -TestWarmup | 5
Name of the Test Scenario | -TestScenario | Default Test Scenario
Enter your API Key | -TestApiKey | UnregisteredTest
Do you want to share the benchmarks to improve the script | -TestShareBenchmarks | True
Hide the results in the overview listing | -Private | False
Send the share link to an email (advised when doing -Private True) | -Email | *empty*


Sources
=======
* [SQLIO](http://www.microsoft.com/en-us/download/details.aspx?id=20163)
* [DISKSPD](https://github.com/microsoft/diskspd)
* [Measure-DiskPerformance.ps1](https://anothermike2.wordpress.com/2014/04/02/powershell-is-kingmeasure-disk-performance-for-iops-and-transfer-rate/)
