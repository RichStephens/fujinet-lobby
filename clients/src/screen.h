/**
 * @brief FujiNet Game Lobby
 * @author Thomas Cherryhomes <thom dot cherryhomes at gmail dot com>
 * @author Eric Carr          <eric dot carr at gmail dot com>
 * @license gpl v. 3, see LICENSE for details
 * @verbose Screen API
 */

#ifndef SCREEN_H
#define SCREEN_H

#include <stdbool.h>

/**
 * @brief Screen Initialization
 * @return true if completed, false if with error.
 */
bool screen_init(void);

/**
 * @brief Screen done (teardown)
 */
void screen_done(void);

/**
 * @brief show banner
 */
void screen_banner(void);

/**
 * @brief Screen Print error
 */
void screen_print_error(int errno);

#endif /* SCREEN_H */
