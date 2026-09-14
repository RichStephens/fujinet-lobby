/**
 * @brief FujiNet Game Lobby
 * @author Thomas Cherryhomes <thom dot cherryhomes at gmail dot com>
 * @author Eric Carr          <eric dot carr at gmail dot com>
 * @license gpl v. 3, see LICENSE for details
 * @verbose ATARI specific input routines, conforming to ../input.h
 */

#include <conio.h>
#include <atari.h>
#include "../input.h"

/**
 * @brief do ATARI key translation to ASCII
 * @param c ATASCII code
 * @return ASCII code
 */
int atascii_to_key(int c)
{
    switch(c)
    {
        case
    }
}

/**
 * @brief Return if start/select/option pressed?
 */
bool consol_key_pressed(void)
{
    return GTIA_READ.consol ^ 0x07; // Console keys are inverted
}

/**
 * @brief Stick moved or trigger pressed?
 */
bool stick_moved(void)
{
    return OS.stick0 ^ 0x0F; // Joystick direction inverted
}

/**
 * @brief convert stick to keypress
 * @return Equivalent keyboard character
 */
char stick_to_key(uint8_t c)
{
    c ^= 0x0F;

    if (c&0x01)
        return '-';
    else if (c&0x02)
        return '=';
    else if (c&0x04)
        return '+';
    else if (c&0x08)
        return '*';
}

/**
 * @brief Input initialization
 * @return true if OK, otherwise false
 */
bool input_init(void)
{
    return true;
}

/**
 * @brief Input done
 */
void input_done(void)
{
}

/**
 * @brief return valid input
 * @verbose from both keyboard and joystick
 * @return a valid 'key' code
 */
int input(void)
{
    while(1)
    {
        if (kbhit())
            return atascii_to_key(cgetc());
        else if(consol_key_pressed())
            return consol_to_key(GTIA_READ.consol);
        else if(stick_moved())
            return stick_to_key(OS.stick0);
    }
}
