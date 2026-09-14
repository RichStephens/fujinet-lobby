/**
 * @brief FujiNet Game Lobby
 * @author Thomas Cherryhomes <thom dot cherryhomes at gmail dot com>
 * @author Eric Carr          <eric dot carr at gmail dot com>
 * @license gpl v. 3, see LICENSE for details
 * @verbose Lobby code
 */

#ifndef LOBBY_H
#define LOBBY_H

#include <stdbool.h>

/**
 * @brief Lobby states
 */
enum _lobbyState
{
    INIT,
    FETCH,
    DISPLAY,
    SELECT,
    MOVE_UP,
    MOVE_DOWN,
    PAGE_UP,
    PAGE_DOWN,
    DONE
} lobbyState = INIT;

/**
 * @brief backbone of lobby
 * @return true if exited ok, otherwise error occurred.
 */
bool lobby(void)
{
    while (lobbyState!=DONE)
    {
        switch(lobbyState)
        {
        case INIT:
            break;
        case FETCH:
            break;
        case DISPLAY:
            break;
        case SELECT:
            break;
        case MOVE_UP:
            break;
        case MOVE_DOWN:
            break;
        case PAGE_UP:
            break;
        case PAGE_DOWN:
            break;
        case DONE:
            break;
        }
    }

    return true;
}

#endif /* LOBBY_H */
