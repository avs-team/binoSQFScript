/* 

Binocular Sample Script for Model 2S Virtual Binoculars

Required files: AVS_VBS3_Plugin_Bino.dll and AVS_VBS3_Plugin_Polhemus.dll
Required version: VBS3 3.7.0 +

Optional Files: 
AVS_Bino_EO.pbo - companion editor object
description.ext containing binoHUD resource class - only required for laser rangefinder functionality

This script operates in conjunction with the binocular plugin to provide a sample implementation of the AVS virtual binoculars model 2S in VBS3

To use this script, add a player named 'observer' to any VBS3 scenario. Place this script in the mission directory and execute it by renaming it 'init.sqf' or from another script or editor object. 

The script will call the 'START_COMMS' function in the binocular plugin (if not already called), which will populate a global variable of type Array named 'binoData' which contains the orientation data from the binoculars. 

The START_COMMS function only needs to be called once per VBS3 session.

If the binoculars are not found, the binoData array will return [0,0,0,0,0]

The first time the START_COMMS function is called, it may require up to 20 seconds to connect to the binoculars

device ID - unique device identifier

gyro X axis, gyro Y axis, gyro Z axis - Xsens gyro data

button status - Button 1 (left button) +1, Button 2 (top left) +4, Button 3 (top right) +2, Button 4 (right button) + 8

Button functions (if enabled)

Button 1 -  cycle view mode
Button 2 - laser rangefinder
Button 3 - digital compass (mils)
Button 4 - hold for 2 secs and release to enter calibration mode

To invoke calibration mode from another client during a network scenario, use publicExec ["player == observer","calibrate = true"];

October 2017
Applied Virtual Simulation Pty Ltd 

For support contact info@appliedvirtual.net

*/
 
/* 
Change these constants to set the axes of pitch / yaw and invert the rotation direction as necessary 
binoData = [x,1,2,3,x]
PolDataa = [x,1,2,3,4,5,6]
*/


APPLY_DOME_CORRECTION = false;
SMOOTHING_ENABLED = true;
POL_SMOOTHING_ENABLED = true;
ENABLE_FUSION = true;


//polhemus configuration
PolDataa = [0,0,0,0,0,0,0,0,0,0];
binoData = [1,1,1,1,0,0,0,0,0];

//Packet element number assignment
xIn = 8;
yIn = 7;
zIn = 9;
yawIn = 3;
pitchIn = 4; 
rollIn = 5;

//Variable assignment
polX = PolDataa select (xIn);
polY = PolDataa select (yIn);
polZ = PolDataa select (zIn);
polYaw = PolDataa select (yawIn);
polPitch = PolDataa select (pitchIn);
polRoll = PolDataa select (rollIn);

//Modifiers
polMovSpeed = -.0303;//multiplier of polMovSpeed:1 ratio 

//Uses the polhemus YAW vs the gyro YAW
usePolPitchYaw = true;

//Set the initial polhemus location 
polPlacementX = 0;
polPlacementY = 0;
polPlacementZ = 0;

//AXIS polarity; set to 1 or -1 to flip axis +- movements
polarityX = 0;
polarityY = 0;
polarityZ = 0;

//offsets
playerOffset = true; //use the players initial starting location as a coordinate offset
offX = 0;
offY = 0;
offZ = 0;

RADIUS = 6; // radius of dome

if (player == observer) then {
	
	if (playerOffset) then {
		offX = getPos player select 0;
		offY = getPos player select 1;
		offZ = getPos player select 2;	
	};

//Previous values for X and Y, used in smoothing algorithm -> starts at players starting point
_oldXPos = offX + polPlacementX;
_oldYPos = offY + polPlacementY;
_oldZPos = offZ + polPlacementZ;
_oldPolYaw = 0;

//bino Local low pass filter variables
_binoYawSmoothArr = [0,0,0,0,0];
_smoothedYaw = 0;
_combinedYawValues = 0;
_smoothingCount = 0;
_oldYaw = 0;

//Offsets applied to yaw and pitch so that north facing is 0,0. R reassigns these to current value
_initialXoffset	= 0;
_initialYoffset = 0;	

//Switches between smoothing methods 1 and 2
SMOOTH_MODE = 1;

binoDir = 0;
binoPitch = 0;

PITCH_AXIS = 5;
YAW_AXIS = 3;

INVERT_PITCH = false;
INVERT_YAW = false;

button1Pressed = false;
button2Pressed = false;
button3Pressed = false;
button4Pressed = false;

buttonAction1 = "calibrate";
buttonAction2 = "calibrate";
buttonAction3 = "calibrate";
buttonAction4 = "calibrate";
						
//Disables falling parachute
observer disableParachute true;
observer allowDamage false;

// Set the binocular state control variables if not already defined by the editor object

if (isNil "AVS_binoControlMode") then {			// 0 - hardware control , 1 - mouse control, 2 - auto target track mode (with editor object)
	AVS_binoControlMode = 0;
};

if (isNil "AVS_enableLaser") then {		// Laser rangefinder HUD object
	AVS_enableLaser = false;
};

if (isNil "AVS_calibrate") then {
	AVS_calibrate = false;
};

if (isNil "AVS_trackTarget") then {			// If a target to track has not been defined by the EO, just select the first vehcile in the scenario
	AVS_trackTarget = allVehicles select 0;
};

	
	hideUI = true;
	
	_startAzimuth = getDir player;	
	_oldFus = 0;
	_binoDir = 0;
	_binoElev = 0;	
	_binoStartDir = 0;
	_binoStartElev = 0;
	_binoCurrentDir = 0;
	_binoCurrentElev = 0;
	_buttonValue = 0;

	_count = 0;

	// ----------- Store the starting orientation of the binoculars -------------
	
	if (binoData select 0 != 0) then {		
		_binoStartDir = binoData select (YAW_AXIS);
		_binoStartElev = binoData select (PITCH_AXIS);
		
		if (INVERT_PITCH) then {
			_binoStartElev = _binoStartElev * -1;
		};
		
		if (INVERT_YAW) then {
			_binoStartDir = _binoStartDir * -1;
		};
	};
	
	// ------ Setup the player with the correct binoculars and have the player avatar arm them ----------
	
	binocularModel = "vbs2_Binocular_UK";		// Define the model of binocular to be used for VBS versions 3.9.1 and above

	if (versionNumber select 0 <= 3 && versionNumber select 1 <= 9 && versionNumber select 2 <= 0) then {		// The model name of the binoculars changed between version 3.9.0 and 3.9.1		
			binocularModel = "vbs2_Binocular_M22";			
	};

	if (binocularWeapon player != binocularModel) then {		
		player removeWeapon (binocularWeapon player);
		player addWeapon binocularModel;
		player addWeapon "NVGoggles";
	};

	//hideUI true;
	// Have the player arm the binoculars - always do this *before* setting external control!

	"Binocular" setAction 1;
	while {currentWeapon player != binocularModel} do {sleep 0.05};
    "Binocular" setAction 0;
	
	//pos for correction algorithm
	_pos = getPos observer;
	
	onEachFrame {
	player setDir (binoDir);
	player setWeaponDirection [[0,(-1*binoPitch)],true];
	player setPos [offX,offY,polZ];
	};
	
	//obtains the initial bino yaw value and subtracts that on bino yaw call
	_initialXoffset = binoData select 3;
	_polYawOffset = 0;
	_polPitchOffset = 0;
	
	sleep 10;

//FUSION FACTOR INITIALIZE: FUSION FACTOR dynamically bridges gap between pol and gyro yaw values at intensity per frame intervals.	
	fusionFactor = 0;
	fusionIntensity = 0.1;
	
//VISUAL CODE REPRESENTATION (SETUPT)
_trackerX = offX;
_trackerY = offY; 
_z = 0; 							// angle value from correction algorithm
_binoYaw = 0; 						// bino yaw value

m1 = createMarker ["m1", [2000,2000,0]];
m1 setMarkerType "Dot";
"m1" setMarkerColor "ColorBlue";
"m1" setMarkerText "Dome Centre";
originPos = getMarkerPos "m1";

m2 = createMarker ["m2", [200,200,0]];
m2 setMarkerType "Dot";
"m2" setMarkerColor "ColorBlack";
"m2" setMarkerText "Polhemus";
"m2" setMarkerPos [(originPos select 0) + polPlacementX, (originPos select 1) + polPlacementY, 0];
polPos = getMarkerPos "m2";

m3 = createMarker ["m3", [200,200,0]];
m3 setMarkerType "Dot";
"m3" setMarkerColor "ColorRed";
"m3" setMarkerText "Bino Position";
"m3" setMarkerPos [(polPos select 0) + _trackerX , (polPos select 1) + _trackerY, 0];


binoPos = getMarkerPos "m3";

_binoYaw = 0;
_z = 0;

OriginLineEnd = [originPos, 10, _binoYaw] call fn_vbs_relPos; 
BinoDirectionLineEnd = [binoPos, 10, _binoYaw] call fn_vbs_relPos;
CorrectedLineEnd = [binoPos,10,_z] call fn_vbs_relPos;

map ctrlSetEventHandler["draw", "(_this select 0) drawEllipse [originPos,6,6,0,[0,0,0,1]]; 
								(_this select 0) drawLine [originPos,OriginLineEnd,[0,0,1,1]]; 
								(_this select 0) drawLine [binoPos,BinoDirectionLineEnd,[1,0,0,1]];
								(_this select 0) drawLine [binoPos,CorrectedLineEnd,[0,1,0,1]];
						"];
	
observer disableGeo [true,false,false,true];
	while {true} do {
		
		sleep .016;
	
		if (isKeyPressed 0x13) then {		// Keyboard Shortcut 'r' 
			
			_initialXoffset = binoData select 3;
			_initialYoffset = binoData select 5;
			
			_polYawOffset = PolDataa select yawIn;
			_polPitchOffset = PolDataa select pitchIn;
	
		};
		
		if (isKeyPressed 0x12) then {		// Keyboard Shortcut 'Q' 
			binoData set [3, ((binoData select 3)+.3)];
		};
		
		if (isKeyPressed 0x10) then {		// Keyboard Shortcut 'E' 
			binoData set [3, ((binoData select 3)-.3)];
		};
		
		if (isKeyPressed 0xC8) then {		// Keyboard Shortcut 'uparrow' 
			PolDataa set [zIn, (( PolDataa select (zIn))+.5)];			
		};
		
		if (isKeyPressed 0xD0) then {		// Keyboard Shortcut 'downarrow' 
			PolDataa set [zIn, (( PolDataa select (zIn))-.5)];
		};
		
		if (isKeyPressed 0x11) then {		// Keyboard Shortcut 'W' 
			PolDataa set [7, ((PolDataa select 7)+.05)];
		};
			
		if (isKeyPressed 0x1F) then {		// Keyboard Shortcut 'S' 
			PolDataa set [7, ((PolDataa select 7)-.05)];
		};
		
		if (isKeyPressed 0x1E) then {		// Keyboard Shortcut 'A' 
			PolDataa set [8, ((PolDataa select 8)-.05)];
		};
			
		if (isKeyPressed 0x20) then {		// Keyboard Shortcut 'D' 
			PolDataa set [8, ((PolDataa select 8)+	.05)];
		};
				
		
		//SET THE POLHEMUS X,Y,Z,Y,P,R to the required values
		polX = (polMovSpeed * (PolDataa select (xIn))) + offX + polPlacementX;
		polY = (polMovSpeed * (PolDataa select (yIn))) + offy + polPlacementY;
		polZ = (polMovSpeed * (PolDataa select (zIn))) + offz + polPlacementZ;
		polYaw = (PolDataa select (yawIn)) - _polYawOffset;
		polPitch = (PolDataa select (pitchIn)) - _polPitchOffset;
		polRoll = PolDataa select (rollIn);
		
		//SMOOTH THE POLHEMUS
		if(POL_SMOOTHING_ENABLED) then {
		_difference = polX - _oldXPos;
		_oldXPos = _oldXPos + 0.2 * (_difference);	
		polX = _oldXPos;
		
		_difference = polY - _oldYPos;
		_oldYPos = _oldYPos + 0.2 * (_difference);	
		polY = _oldYPos;
		
		_difference = polZ - _oldZPos;
		_oldZPos = _oldZPos + 0.2 * (_difference);	
		polZ = _oldZPos;
		
		//_difference = polYaw - _oldPolYaw;
		//_oldPolYaw = _oldPolYaw + 0.05 * (_difference);	
		//polYaw = _oldPolYaw;
		};
		//Set player to players initial pos + the polhemus pos
		//player setPos [polX,polY,polZ];
		
		/* TEST PRINTS
		teststring = "CORRECTION TEST OUTPUT:"
		+ "\nBINODIR NO CORRECT: " + str(_smoothedYaw)
		+ "\nCORRECTED: " + str(alpha)
		+ "\nXOFFSET: " + str(_initialXoffset)
		+ "\nYOFFSET: " + str(_initialYoffset)
		+ "\nPITCH: " + str(binoPitch)
		
		+ "\nZ VALUE: " + str(polZ)
		+ "\nPlayer Z: " + str(getPos player select 2)
		
		+ "\n\nRAW POL  " + str(polYaw)
		+ "\nRAW GYRO   "+str(_smoothedYaw)
		+ "\nRAW FUSION" + str(_oldFus)
		
		+ "\n\nSTARTING POS AND NEW POS:"
		+ "\nSTART X PLAYER: " + str(offX)
		+ "\nSTART Y PLAYER: " + str(offY)
		+ "\nSTART Z PLAYER: " + str(offY)
		+ "\nACTUAL X PLAYER: " + str(getPos player select 0)
		+ "\nACTUAL Y PLAYER: " + str(getPos player select 1)
		+ "\nACTUAL Z PLAYER: " + str(getPos player select 2)		
		
		+ "\nPOL X: " + str(Polx-offX-polPlacementX)
		+ "\nPOL Y: " + str(Poly-offY-polPlacementY);
		
		hint teststring;
		*/
		
		//Martins initial block
		if (AVS_binoControlMode == 0) then {					// Binoculars controlled by hardware device
			if ((binoData select 0) == 0) then {
				AVS_binoControlMode = 1;
				hint "Binoculars Not Found\nReverting to Mouse Movement";
				publicVariable "AVS_binoControlMode";
			} else {
				if (!getExternalControl player) then { 
						player setExternalControl true;
						setOpticsState [true,4,0,0,binocularModel,-1,0,0];
						player disableGunnerInput 3;
						//hideUI true;
				};	
											
				_binoCurrentElev = binoData select PITCH_AXIS;
				
				if (INVERT_PITCH) then {
					_binoCurrentElev = _binoCurrentElev * -1;
				};
				
				_binoCurrentDir = binoData select YAW_AXIS;
								
		//SMOOTHING FOR BINO YAW
		if (SMOOTHING_ENABLED) then {
				_binoDir = ((-1)*(binoData select (YAW_AXIS))- (-1)*_initialXoffset) + fusionFactor;	
			
			
				//Fusion value to slowly bridge gap between the 2 yaws
				if(ENABLE_FUSION) then {
			
					if(_smoothedYaw < 0) then {
						_smoothedYaw = _smoothedYaw + 360;
					};
					if(polYaw < 0) then {
						polYaw = polYaw + 360;
					};
			
				//CALCULATE FUSION
				_difference = _binoDir - polYaw;
				
				if(_difference < -2 || _difference > 2) then{
				fusionFactor = fusionFactor + -fusionIntensity* (_difference);	
				};
				
				outstream = "\n\nAFTER CORRECTION:\n\nPOL YAW: " + str(polYaw)
				+ "\nGYRO YAW: " + str(_smoothedYaw) 
				+ "\nFUSIONFACTOR: " + str(fusionFactor)
				+ "\nDIFF: " + str(_difference);
				
				hint outstream;
				
				
				_difference = polX - _oldXPos;
				_oldXPos = _oldXPos + 0.2 * (_difference);	
				polX = _oldXPos;
				
			};
				
			if(SMOOTH_MODE == 1) then {
				_smoothingCount = _smoothingCount + 1;
					
				if(_smoothingCount >= 5) then {
					_smoothingCount =  0;
				};				
				_binoYawSmoothArr set [_smoothingCount, _binoDir];
				_combinedYawValues = 0;					
				{
					_combinedYawValues = _combinedYawValues + _x;
				} forEach _binoYawSmoothArr;
					
				_smoothedYaw = _combinedYawValues / 5;										
									
				_binoDir  = _smoothedYaw;						
			} else {
				_difference = _binoDir - _oldYaw;
				_oldYaw = _oldYaw + 0.1 * (_difference);
				_binoDir = _oldYaw;			
			};
							
							
		};//BINO SMOOTHING END; _binoDir is smoothed and has initial yaw offset applied
				
	//ANGLE CORRECTION CODE
	//Variables for targetPoint calculation
	if(APPLY_DOME_CORRECTION)then{
	
	_posX = (_pos select 0);
	_posY = (_pos select 1);
	
	//calculation of targetPoint
	_radius = RADIUS;
	_targetY = (_radius*sin -(_smoothedYaw -90)) + _posY;
	_targetX = (_radius*cos -(_smoothedYaw -90)) + _posX;
	
	//variables for alpha Calculation.
	_currentPos = [polX,polY,polZ];
	_currentX = _currentPos select 0;
	_currentY = _currentPos select 1;
	
	//calculation of alpha
	_xComponent = _targetx - _currentX;
	_yComponent =  _targetY - _currentY;
	_ratio = _xComponent/_yComponent;
	alpha = atan(_ratio);
	
	//correction of alpha depending on the position of the target and the binos
	if (_targetY>=_currentY) then 
	{
		alpha = alpha-90;
	};
	if (_targetY<_currentY) then 
	{
		alpha =90+alpha;
	};
	
	alpha = alpha + 90;
	}else{
		alpha = _smoothedYaw;
	};
	
	//setting of the binos direction
	//hint format["Yaw: %1\nTarget X: %2\nTarget Y: %3\n Binos X:%4\n Binos Y: %5\n Alpha %6\n Polx: %7\n",_binoDir,_targetX,_targetY,_currentX,_currentY,alpha ,(polY-offX)];

		
		if (INVERT_PITCH) then {
			binoPitch = (_binoCurrentElev-_initialYoffset)*-1;
		}else{
			binoPitch = (_binoCurrentElev-_initialYoffset);
		};
		
		binoDir = (alpha);	
	

			polPos = getMarkerPos "m2";
			binoPos = getMarkerPos "m3";
			_trackerX = (polMovSpeed * (PolDataa select (xIn))); // update me
			_trackerY = (polMovSpeed * (PolDataa select (YIn))); // update me
			_binoYaw = _smoothedYaw; // update me
			_z = alpha;
			OriginLineEnd = [originPos, 10, _binoYaw] call fn_vbs_relPos; 
			BinoDirectionLineEnd = [binoPos, 10, _binoYaw] call fn_vbs_relPos;
			CorrectedLineEnd = [binoPos,10,_z] call fn_vbs_relPos;
			"m3" setMarkerPos [(polPos select 0) +  _trackerX	,(polPos select 1)	+ _trackerY ,0];
				
				
			};
		} 
		
		elseif (AVS_binoControlMode == 1) then {				// Binoculars Controlled by mouse movement on local machine
			if (getExternalControl player) then { 
				player setExternalControl false;
				player disableGunnerInput 0;
				//hideUI false;
			};
		} 
		
		elseif (AVS_binoControlMode == 2) then {				// Binoculars controlled by autotrack target mode
			if (!getExternalControl player) then { 
					player setExternalControl true;
					setOpticsState [true,4,0,0,binocularModel,-1,0,0];
					player disableGunnerInput 3;
					//hideUI true;
			};
			if (!isNil "AVS_trackTarget") then {
				_veh = AVS_trackTarget;
				_vehDir = [player, getpos _veh] call fn_vbs_dirTo;
				_vehDist2D = [player,_veh] call fn_vbs_distance2D;
				_vehAlt = (getPosASL2 _veh select 2) - (getPosASL2 player select 2);	
				_vehElev = atan(_vehAlt / _vehDist2D);
				_binoDir = _vehDir;
				_binoElev = _vehElev;			
				player setDir  _binoDir; 
				player setWeaponDirection [[0,_binoElev],true];
			} else {
				hint "No vehicles found in scenario\nReverting to Mouse control mode";
				AVS_binoControlMode = 1;
				publicVariable "AVS_binoControlMode";
			};
		};
		
		if (AVS_enableLaser) then {
			// check if the resource is open, if not assign variables to it		
			if (isNull BinoDisplay) then {
				titleRsc["BinoHUD","PLAIN"];
			};
			
		} else {
			if (!isNull BinoDisplay) then {		// Turn off the display
				titleRsc["DEFAULT","PLAIN"];
			};
		};
		
		if (!(opticsState select 0)) then {			// check to make sure the bino player is still using optics
			setOpticsState [true,4,0,0,binocularModel,-1,0,0];
		};
		
		
		// ------------- Logic for handling device button presses ---------------------
		
		_buttonValue = binoData select 4;
		
		if (_buttonValue >= 8 ) then {
			button1Pressed = true;
			_buttonValue = _buttonValue - 8;
		} else {
			button1Pressed = false;
		};		
		if (_buttonValue >= 4 ) then {
			button2Pressed = true;
			_buttonValue = _buttonValue - 4;
		} else {
			button2Pressed = false;
		};		
		if (_buttonValue >= 2 ) then {
			button3Pressed = true;
			_buttonValue = _buttonValue - 2;
		} else {
			button3Pressed = false;
		};		
		if (_buttonValue >= 1 ) then {
			button4Pressed = true;
			_buttonValue = _buttonValue - 1;
		} else {
			button4Pressed = false;
		};
		
		if (button1Pressed || button2Pressed || button3Pressed || button4Pressed ) then {
			if (binoData select 0 != 0) then {		
			
			
				_binoStartDir = binoData select (YAW_AXIS);
				
				
				_binoStartElev = binoData select (PITCH_AXIS);
				
				if (INVERT_PITCH) then {
					_binoStartElev = _binoStartElev * -1;
				};
				
				if (INVERT_YAW) then {
					_binoStartDir = _binoStartDir * -1;
				};
			};		
		};
		
	};
};