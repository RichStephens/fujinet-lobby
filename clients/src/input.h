/**
 * @brief FujiNet Game Lobby
 * @author Thomas Cherryhomes <thom dot cherryhomes at gmail dot com>
 * @author Eric Carr          <eric dot carr at gmail dot com>
 * @license gpl v. 3, see LICENSE for details
 * @verbose Input API
 */

#ifndef INPUT_H
#define INPUT_H

#include <stdbool.h>

/**
 * @brief Input initialization
 * @return true if OK, otherwise false
 */
bool input_init(void);

/**
 * @brief Input done
 */
void input_done(void);

/**
 * @brief Get valid input from valid input devices
 */
int input(void);

#endif /* INPUT_H */
