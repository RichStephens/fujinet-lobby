#ifdef _CMOC_VERSION_

#include <stdint.h>
#include <coco.h>
#include <joystick.h>
#include "../fujinet-fuji.h"

extern char panel_spacer_string[];
extern DeviceSlot device_slots[1];

unsigned char readJoystick() {
return 0;
}


void initialize() {
  initCoCoSupport();

  if (!isCoCo3) {
    // Colored dashes don't look good on non coco3
    strcpy(panel_spacer_string, "--------");
  }
}

void waitvsync() {
    setTimer(0);
    
    while (!getTimer());
}

/// @brief Invokes the CoCo BASIC RUNM command
/// @param filename 
void runm(char * filename) 
{
    // This reproduces the state when executing RUNM"FILE in BASIC
    // by filling in the command line buffer and jumping directly
    // to the Basic RUN procedure

    // Set beginning of (compressed) command: M"
    *((uint16_t*)0x2dd)=0x4D22;

    // Add the filename to the command
    strcpy(0x2df,filename);

    // Set command pointer
    *((uint16_t*)0xa6)=0x2dd; // set CHARAD
    
    // Jump to "RUNM" command
    asm
    {
        // Observed this value in actual RUNM. Not working unless 4Dxx is set
        ldd     #$4D1C

        // Jump to RUN procedure
        jmp     $AE75
    }
}

void reboot(void)
{
  // No need to reboot - just RUNM the game
  static uint8_t i;
  static char *filename;
  
  filename = device_slots[0].file;

  // Strip path from filename, converting to uppercase
  for(i=strlen(filename)-1;i<=255;i--) {
    if (filename[i]== '/') {
      filename=&filename[i+1];
      break;
    } else {
      if (filename[i]>=97 && filename[i]<=122 )
        filename[i]-=32;
    }
  }
  
  // Remove extension
  if (strstr(filename, "."))
    *((char*)strstr(filename, "."))=0;

  // Run the .bin file by the same name as the filename
  runm(filename); 
}

#endif /* _CMOC_VERSION_ */