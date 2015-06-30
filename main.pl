#/usr/bin/perl
use strict;
use Time::HiRes qw/ time sleep /;

our $HOSTNAME = `hostname -s`;
chomp($HOSTNAME);
our $HOME = $ENV{"HOME"};
our $SCRIPTDIR = "$HOME/bin";
require "$SCRIPTDIR/mySubs.pl";
require "$SCRIPTDIR/usbRelay.pl";
require "$SCRIPTDIR/copyGoPro.pl";
require "$SCRIPTDIR/Upload.pl";
require "$SCRIPTDIR/GPS.pl";
#require "$SCRIPTDIR/Backup.pl";
require "$SCRIPTDIR/cleanup.pl";
require "$SCRIPTDIR/RecordTime.pl";

our @PitStopRegion;
our @Regions;
our @RegionCamera;
require "$SCRIPTDIR/map.data";
our %cameraID;
require "$SCRIPTDIR/camera.data";

our $PSDir = "$HOME/PS";
our $withinPitStop;
our $withinTrack;
our %GPS;
our %GPSmeta;
our @GPSLog;
our @Region;
our $des;
our $serPort;
my $oldtrigger="hello";
my $trigger;
our $debug = 1;

our $PSlogfile="$HOME/PS/PS.log";
&mySystem("rm -f $PSlogfile");

&myPrintTime("1. Start ");

&myPrintTime("2. Found GPS Unit, read in meta ");
&mySystem("rm -f $HOME/PS/data.run");
&mySystem("rm -f $HOME/PS/log.run");
&mySystem("rm -f $HOME/PS/RaceData.data");
&mySystem("rm -f $HOME/PS/RaceData.log");
system ('gnome-terminal', '-x', 'sh', '-c', 'cd $HOME/RaceCapture_App; python main.py');
sleep(40);
&mySystem("touch ~/PS/log.run"); 

&myPrintTime("3. Found USB Relay, turn all cameras OFF ");

&USBInit();
&RecordInit();
&USBCameraOff();
&GoProPowerOn();
&GoProPowerOff();

&myPrintTime("4. Switch on Camera USB, Switch on Camera Power ");

&myPrintTime("5. Found Cameras ");

&myPrintTime("6. Send Server Ready ");

&myPrintTime("7. Switch off Camera Power, Switch off Camera USB");

&myPrintTime("8.1 Init GPS Data ");
&ParseGPSMeta("$HOME/PS/RaceData.meta");

my $lat =0;
my $long =0;
while( abs($lat)< 1e-6 && abs($long) < 1e-6){
    &mySpeak("Aquiring GPS Signal");
    &ParseGPSData("$HOME/PS/RaceData.log", \%GPS);
    $lat = $GPS{"Latitude"};
    $long = $GPS{"Longitude"};
    sleep(10);
}
&mySpeak("GPS Signal aquired");

my $fullloop=1;
while($fullloop){
  open(TEST, "</home/k/bin/temp");
  $oldtrigger=<TEST>; chomp($oldtrigger);
  close(TEST);

  &myPrintTime("8. Reading GPS location, Speed ");
  $withinPitStop = 1;
  &RecordInit();
  my $sec=0;
  while($withinPitStop){
    sleep(0.1);
    &ParseGPSData("$HOME/PS/RaceData.log", \%GPS);
    my $lat = $GPS{"Latitude"};
    my $long = $GPS{"Longitude"};
    my $speed = $GPS{"Speed"};
    open(TEST, "</home/k/bin/temp");
    $trigger=<TEST>; chomp($trigger);
    close(TEST); 
    $withinPitStop = &withinRegion( $lat, $long, \@PitStopRegion );
    if($sec % 10 ==0){
      &myPrint("In PitStopRegion: Latitude $lat; Longitude $long; within $withinPitStop\n");
      $sec=0;
    }
    $sec++;    
    if( $debug ==1 ){
       if($trigger ne $oldtrigger){
	 $withinPitStop = 0;
         $oldtrigger = $trigger ;
       } else {
         $withinPitStop = 1
       }  
    }
  }

  &myPrintTime("9. Start Racing ");
  &mySystem("touch ~/PS/RaceData.log");
  &GoProPowerOn();
  $des =  "$HOSTNAME.".&myTimeDir();
  &mySpeak("Recording Started");

# Starting Recording Squence
  &myPrintTime("10. Starting Recording Squence... ");
  my $inRace=1;
  my $currentRegionIndex=-1;
  my $currentCamera=-1;
  my $nextRegionIndex=0;
  my $nextRegionRef=$Regions[$nextRegionIndex];
  my $nextCamera=$RegionCamera[$nextRegionIndex];
  my $totalRegion=$#Regions+1;
  while($inRace){
    &ParseGPSData("$HOME/PS/RaceData.log", \%GPS);
    my $lat = $GPS{"Latitude"};
    my $long = $GPS{"Longitude"};
    my $speed = $GPS{"Speed"};
    my $RPM = $GPS{"RPM"};
    my $EngineTemp = $GPS{"EngineTemp"};
    my $AccelX = $GPS{"AccelX"};
    my $AccelY = $GPS{"AccelY"};
    my $AccelZ = $GPS{"AccelZ"};
    open(TEST, "</home/k/bin/temp");
    $trigger=<TEST>; chomp($trigger);
    close(TEST);
    my $withinNextRegion = &withinRegion( $lat, $long, $nextRegionRef );
#    print("Region $currentRegionIndex, next $nextRegionIndex, withnext $withinNextRegion \n");
    if( $debug ==1 && ($trigger ne $oldtrigger)){
	$withinNextRegion = 1;
        $oldtrigger = $trigger;
    }
    if( $withinNextRegion ){
	if( $currentRegionIndex==-1 ){
            &GoProRecordStart($nextCamera);
            &myPrintTime("  Start Camera $nextCamera : ");
        } else {
            &GoProRecordSwitch($nextCamera, $currentCamera); 
            &myPrintTime("  Change Camera from $currentCamera to $nextCamera : ");
        }
        $currentCamera=$nextCamera;
        $currentRegionIndex=$nextRegionIndex;
        $nextRegionIndex=($nextRegionIndex+1) % $totalRegion ;
        $nextRegionRef=$Regions[$nextRegionIndex];
        $nextCamera=$RegionCamera[$nextRegionIndex];        
    }
    my $withinPitStop = &withinRegion( $lat, $long, \@PitStopRegion );
    if(  $debug ==1 ) {
       if ($trigger =~ /STOP/){
	$withinPitStop = 1;
       } else { 
	$withinPitStop = 0;
       }
    }    
    if( $withinPitStop ){
        &GoProRecordStop($currentCamera);
        &myPrintTime("  Stop Camera $currentCamera : ");
        $currentRegionIndex=-1;
        $currentCamera=-1;
        $nextRegionIndex=0;
        $inRace=0;
    }
    sleep(0.1);
    if($sec % 10 ==0){
      &myPrint("In Region $currentRegionIndex: next $nextRegionIndex: Latitude $lat; Longitude $long\n");
      $sec=0;
    }
    $sec++;    
  }

  &mySpeak("Recording Stopped");
# Ending Recording Squence

  &myPrintTime("11. Car is off Track, stop recording, turn off camera, switch on camera USB, turn on camera ");
  &GoProPowerOff();
  &USBCameraOn();
  &GoProPowerOn();
  &mySystem("rm -f ~/PS/data.run");
  &mySpeak("Downloading images to computer");

  &myPrintTime("12. copyGoPro ");
  &copyGoPro("$HOME/$des");

  &myPrintTime("13. switch off camera, switch off camera USB ");

  &myPrintTime("14. cut media ");
  &createVideoList();
  &renameFiles("$HOME/$des");

  &myPrintTime("15. upload to server wifi ");
  &mySpeak("Uploading to Server");
  &Upload("$HOME/$des", $des);
  &mySpeak("Uploading complete");

  &myPrintTime("16. send server ready signal ");

  &GoProPowerOff();
  &USBCameraOff();

  &myPrintTime("17. backup to hard drive ");


  &myPrintTime("18. loop back ");
#  &cleanup();

  if( $debug ==1 ){$fullloop=0;}
}
#/usr/bin/perl
use strict;
use Time::HiRes qw/ time sleep /;

our $HOSTNAME = `hostname -s`;
chomp($HOSTNAME);
our $HOME = $ENV{"HOME"};
our $SCRIPTDIR = "$HOME/bin";
require "$SCRIPTDIR/mySubs.pl";
require "$SCRIPTDIR/usbRelay.pl";
require "$SCRIPTDIR/copyGoPro.pl";
require "$SCRIPTDIR/Upload.pl";
require "$SCRIPTDIR/GPS.pl";
#require "$SCRIPTDIR/Backup.pl";
require "$SCRIPTDIR/cleanup.pl";
require "$SCRIPTDIR/RecordTime.pl";

our @PitStopRegion;
our @Regions;
our @RegionCamera;
require "$SCRIPTDIR/map.data";
our %cameraID;
require "$SCRIPTDIR/camera.data";

our $PSDir = "$HOME/PS";
our $withinPitStop;
our $withinTrack;
our %GPS;
our %GPSmeta;
our @GPSLog;
our @Region;
our $des;
our $serPort;
my $oldtrigger="hello";
my $trigger;
our $debug = 1;

our $PSlogfile="$HOME/PS/PS.log";
&mySystem("rm -f $PSlogfile");

&myPrintTime("1. Start ");

&myPrintTime("2. Found GPS Unit, read in meta ");
&mySystem("rm -f $HOME/PS/data.run");
&mySystem("rm -f $HOME/PS/log.run");
&mySystem("rm -f $HOME/PS/RaceData.data");
&mySystem("rm -f $HOME/PS/RaceData.log");
system ('gnome-terminal', '-x', 'sh', '-c', 'cd $HOME/RaceCapture_App; python main.py');
sleep(40);
&mySystem("touch ~/PS/log.run"); 

&myPrintTime("3. Found USB Relay, turn all cameras OFF ");

&USBInit();
&RecordInit();
&USBCameraOff();
&GoProPowerOn();
&GoProPowerOff();

&myPrintTime("4. Switch on Camera USB, Switch on Camera Power ");

&myPrintTime("5. Found Cameras ");

&myPrintTime("6. Send Server Ready ");

&myPrintTime("7. Switch off Camera Power, Switch off Camera USB");

&myPrintTime("8.1 Init GPS Data ");
&ParseGPSMeta("$HOME/PS/RaceData.meta");

my $lat =0;
my $long =0;
while( abs($lat)< 1e-6 && abs($long) < 1e-6){
    &mySpeak("Aquiring GPS Signal");
    &ParseGPSData("$HOME/PS/RaceData.log", \%GPS);
    $lat = $GPS{"Latitude"};
    $long = $GPS{"Longitude"};
    sleep(10);
}
&mySpeak("GPS Signal aquired");

my $fullloop=1;
while($fullloop){
  open(TEST, "</home/k/bin/temp");
  $oldtrigger=<TEST>; chomp($oldtrigger);
  close(TEST);

  &myPrintTime("8. Reading GPS location, Speed ");
  $withinPitStop = 1;
  &RecordInit();
  my $sec=0;
  while($withinPitStop){
    sleep(0.1);
    &ParseGPSData("$HOME/PS/RaceData.log", \%GPS);
    my $lat = $GPS{"Latitude"};
    my $long = $GPS{"Longitude"};
    my $speed = $GPS{"Speed"};
    open(TEST, "</home/k/bin/temp");
    $trigger=<TEST>; chomp($trigger);
    close(TEST); 
    $withinPitStop = &withinRegion( $lat, $long, \@PitStopRegion );
    if($sec % 10 ==0){
      &myPrint("In PitStopRegion: Latitude $lat; Longitude $long; within $withinPitStop\n");
      $sec=0;
    }
    $sec++;    
    if( $debug ==1 ){
       if($trigger ne $oldtrigger){
	 $withinPitStop = 0;
         $oldtrigger = $trigger ;
       } else {
         $withinPitStop = 1
       }  
    }
  }

  &myPrintTime("9. Start Racing ");
  &mySystem("touch ~/PS/RaceData.log");
  &GoProPowerOn();
  $des =  "$HOSTNAME.".&myTimeDir();
  &mySpeak("Recording Started");

# Starting Recording Squence
  &myPrintTime("10. Starting Recording Squence... ");
  my $inRace=1;
  my $currentRegionIndex=-1;
  my $currentCamera=-1;
  my $nextRegionIndex=0;
  my $nextRegionRef=$Regions[$nextRegionIndex];
  my $nextCamera=$RegionCamera[$nextRegionIndex];
  my $totalRegion=$#Regions+1;
  while($inRace){
    &ParseGPSData("$HOME/PS/RaceData.log", \%GPS);
    my $lat = $GPS{"Latitude"};
    my $long = $GPS{"Longitude"};
    my $speed = $GPS{"Speed"};
    my $RPM = $GPS{"RPM"};
    my $EngineTemp = $GPS{"EngineTemp"};
    my $AccelX = $GPS{"AccelX"};
    my $AccelY = $GPS{"AccelY"};
    my $AccelZ = $GPS{"AccelZ"};
    open(TEST, "</home/k/bin/temp");
    $trigger=<TEST>; chomp($trigger);
    close(TEST);
    my $withinNextRegion = &withinRegion( $lat, $long, $nextRegionRef );
#    print("Region $currentRegionIndex, next $nextRegionIndex, withnext $withinNextRegion \n");
    if( $debug ==1 && ($trigger ne $oldtrigger)){
	$withinNextRegion = 1;
        $oldtrigger = $trigger;
    }
    if( $withinNextRegion ){
	if( $currentRegionIndex==-1 ){
            &GoProRecordStart($nextCamera);
            &myPrintTime("  Start Camera $nextCamera : ");
        } else {
            &GoProRecordSwitch($nextCamera, $currentCamera); 
            &myPrintTime("  Change Camera from $currentCamera to $nextCamera : ");
        }
        $currentCamera=$nextCamera;
        $currentRegionIndex=$nextRegionIndex;
        $nextRegionIndex=($nextRegionIndex+1) % $totalRegion ;
        $nextRegionRef=$Regions[$nextRegionIndex];
        $nextCamera=$RegionCamera[$nextRegionIndex];        
    }
    my $withinPitStop = &withinRegion( $lat, $long, \@PitStopRegion );
    if(  $debug ==1 ) {
       if ($trigger =~ /STOP/){
	$withinPitStop = 1;
       } else { 
	$withinPitStop = 0;
       }
    }    
    if( $withinPitStop ){
        &GoProRecordStop($currentCamera);
        &myPrintTime("  Stop Camera $currentCamera : ");
        $currentRegionIndex=-1;
        $currentCamera=-1;
        $nextRegionIndex=0;
        $inRace=0;
    }
    sleep(0.1);
    if($sec % 10 ==0){
      &myPrint("In Region $currentRegionIndex: next $nextRegionIndex: Latitude $lat; Longitude $long\n");
      $sec=0;
    }
    $sec++;    
  }

  &mySpeak("Recording Stopped");
# Ending Recording Squence

  &myPrintTime("11. Car is off Track, stop recording, turn off camera, switch on camera USB, turn on camera ");
  &GoProPowerOff();
  &USBCameraOn();
  &GoProPowerOn();
  &mySystem("rm -f ~/PS/data.run");
  &mySpeak("Downloading images to computer");

  &myPrintTime("12. copyGoPro ");
  &copyGoPro("$HOME/$des");

  &myPrintTime("13. switch off camera, switch off camera USB ");

  &myPrintTime("14. cut media ");
  &createVideoList();
  &renameFiles("$HOME/$des");

  &myPrintTime("15. upload to server wifi ");
  &mySpeak("Uploading to Server");
  &Upload("$HOME/$des", $des);
  &mySpeak("Uploading complete");

  &myPrintTime("16. send server ready signal ");

  &GoProPowerOff();
  &USBCameraOff();

  &myPrintTime("17. backup to hard drive ");


  &myPrintTime("18. loop back ");
#  &cleanup();

  if( $debug ==1 ){$fullloop=0;}
}
#/usr/bin/perl
use strict;
use Time::HiRes qw/ time sleep /;

our $HOSTNAME = `hostname -s`;
chomp($HOSTNAME);
our $HOME = $ENV{"HOME"};
our $SCRIPTDIR = "$HOME/bin";
require "$SCRIPTDIR/mySubs.pl";
require "$SCRIPTDIR/usbRelay.pl";
require "$SCRIPTDIR/copyGoPro.pl";
require "$SCRIPTDIR/Upload.pl";
require "$SCRIPTDIR/GPS.pl";
#require "$SCRIPTDIR/Backup.pl";
require "$SCRIPTDIR/cleanup.pl";
require "$SCRIPTDIR/RecordTime.pl";

our @PitStopRegion;
our @Regions;
our @RegionCamera;
require "$SCRIPTDIR/map.data";
our %cameraID;
require "$SCRIPTDIR/camera.data";

our $PSDir = "$HOME/PS";
our $withinPitStop;
our $withinTrack;
our %GPS;
our %GPSmeta;
our @GPSLog;
our @Region;
our $des;
our $serPort;
my $oldtrigger="hello";
my $trigger;
our $debug = 1;

our $PSlogfile="$HOME/PS/PS.log";
&mySystem("rm -f $PSlogfile");

&myPrintTime("1. Start ");

&myPrintTime("2. Found GPS Unit, read in meta ");
&mySystem("rm -f $HOME/PS/data.run");
&mySystem("rm -f $HOME/PS/log.run");
&mySystem("rm -f $HOME/PS/RaceData.data");
&mySystem("rm -f $HOME/PS/RaceData.log");
system ('gnome-terminal', '-x', 'sh', '-c', 'cd $HOME/RaceCapture_App; python main.py');
sleep(40);
&mySystem("touch ~/PS/log.run"); 

&myPrintTime("3. Found USB Relay, turn all cameras OFF ");

&USBInit();
&RecordInit();
&USBCameraOff();
&GoProPowerOn();
&GoProPowerOff();

&myPrintTime("4. Switch on Camera USB, Switch on Camera Power ");

&myPrintTime("5. Found Cameras ");

&myPrintTime("6. Send Server Ready ");

&myPrintTime("7. Switch off Camera Power, Switch off Camera USB");

&myPrintTime("8.1 Init GPS Data ");
&ParseGPSMeta("$HOME/PS/RaceData.meta");

my $lat =0;
my $long =0;
while( abs($lat)< 1e-6 && abs($long) < 1e-6){
    &mySpeak("Aquiring GPS Signal");
    &ParseGPSData("$HOME/PS/RaceData.log", \%GPS);
    $lat = $GPS{"Latitude"};
    $long = $GPS{"Longitude"};
    sleep(10);
}
&mySpeak("GPS Signal aquired");

my $fullloop=1;
while($fullloop){
  open(TEST, "</home/k/bin/temp");
  $oldtrigger=<TEST>; chomp($oldtrigger);
  close(TEST);

  &myPrintTime("8. Reading GPS location, Speed ");
  $withinPitStop = 1;
  &RecordInit();
  my $sec=0;
  while($withinPitStop){
    sleep(0.1);
    &ParseGPSData("$HOME/PS/RaceData.log", \%GPS);
    my $lat = $GPS{"Latitude"};
    my $long = $GPS{"Longitude"};
    my $speed = $GPS{"Speed"};
    open(TEST, "</home/k/bin/temp");
    $trigger=<TEST>; chomp($trigger);
    close(TEST); 
    $withinPitStop = &withinRegion( $lat, $long, \@PitStopRegion );
    if($sec % 10 ==0){
      &myPrint("In PitStopRegion: Latitude $lat; Longitude $long; within $withinPitStop\n");
      $sec=0;
    }
    $sec++;    
    if( $debug ==1 ){
       if($trigger ne $oldtrigger){
	 $withinPitStop = 0;
         $oldtrigger = $trigger ;
       } else {
         $withinPitStop = 1
       }  
    }
  }

  &myPrintTime("9. Start Racing ");
  &mySystem("touch ~/PS/RaceData.log");
  &GoProPowerOn();
  $des =  "$HOSTNAME.".&myTimeDir();
  &mySpeak("Recording Started");

# Starting Recording Squence
  &myPrintTime("10. Starting Recording Squence... ");
  my $inRace=1;
  my $currentRegionIndex=-1;
  my $currentCamera=-1;
  my $nextRegionIndex=0;
  my $nextRegionRef=$Regions[$nextRegionIndex];
  my $nextCamera=$RegionCamera[$nextRegionIndex];
  my $totalRegion=$#Regions+1;
  while($inRace){
    &ParseGPSData("$HOME/PS/RaceData.log", \%GPS);
    my $lat = $GPS{"Latitude"};
    my $long = $GPS{"Longitude"};
    my $speed = $GPS{"Speed"};
    my $RPM = $GPS{"RPM"};
    my $EngineTemp = $GPS{"EngineTemp"};
    my $AccelX = $GPS{"AccelX"};
    my $AccelY = $GPS{"AccelY"};
    my $AccelZ = $GPS{"AccelZ"};
    open(TEST, "</home/k/bin/temp");
    $trigger=<TEST>; chomp($trigger);
    close(TEST);
    my $withinNextRegion = &withinRegion( $lat, $long, $nextRegionRef );
#    print("Region $currentRegionIndex, next $nextRegionIndex, withnext $withinNextRegion \n");
    if( $debug ==1 && ($trigger ne $oldtrigger)){
	$withinNextRegion = 1;
        $oldtrigger = $trigger;
    }
    if( $withinNextRegion ){
	if( $currentRegionIndex==-1 ){
            &GoProRecordStart($nextCamera);
            &myPrintTime("  Start Camera $nextCamera : ");
        } else {
            &GoProRecordSwitch($nextCamera, $currentCamera); 
            &myPrintTime("  Change Camera from $currentCamera to $nextCamera : ");
        }
        $currentCamera=$nextCamera;
        $currentRegionIndex=$nextRegionIndex;
        $nextRegionIndex=($nextRegionIndex+1) % $totalRegion ;
        $nextRegionRef=$Regions[$nextRegionIndex];
        $nextCamera=$RegionCamera[$nextRegionIndex];        
    }
    my $withinPitStop = &withinRegion( $lat, $long, \@PitStopRegion );
    if(  $debug ==1 ) {
       if ($trigger =~ /STOP/){
	$withinPitStop = 1;
       } else { 
	$withinPitStop = 0;
       }
    }    
    if( $withinPitStop ){
        &GoProRecordStop($currentCamera);
        &myPrintTime("  Stop Camera $currentCamera : ");
        $currentRegionIndex=-1;
        $currentCamera=-1;
        $nextRegionIndex=0;
        $inRace=0;
    }
    sleep(0.1);
    if($sec % 10 ==0){
      &myPrint("In Region $currentRegionIndex: next $nextRegionIndex: Latitude $lat; Longitude $long\n");
      $sec=0;
    }
    $sec++;    
  }

  &mySpeak("Recording Stopped");
# Ending Recording Squence

  &myPrintTime("11. Car is off Track, stop recording, turn off camera, switch on camera USB, turn on camera ");
  &GoProPowerOff();
  &USBCameraOn();
  &GoProPowerOn();
  &mySystem("rm -f ~/PS/data.run");
  &mySpeak("Downloading images to computer");

  &myPrintTime("12. copyGoPro ");
  &copyGoPro("$HOME/$des");

  &myPrintTime("13. switch off camera, switch off camera USB ");

  &myPrintTime("14. cut media ");
  &createVideoList();
  &renameFiles("$HOME/$des");

  &myPrintTime("15. upload to server wifi ");
  &mySpeak("Uploading to Server");
  &Upload("$HOME/$des", $des);
  &mySpeak("Uploading complete");

  &myPrintTime("16. send server ready signal ");

  &GoProPowerOff();
  &USBCameraOff();

  &myPrintTime("17. backup to hard drive ");


  &myPrintTime("18. loop back ");
#  &cleanup();

  if( $debug ==1 ){$fullloop=0;}
}
