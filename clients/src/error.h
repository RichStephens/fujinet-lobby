/**
 * @brief FujiNet Game Lobby
 * @author Thomas Cherryhomes <thom dot cherryhomes at gmail dot com>
 * @author Eric Carr          <eric dot carr at gmail dot com>
 * @license gpl v. 3, see LICENSE for details
 * @verbose Error enum
 */

#ifndef ERROR_H
#define ERROR_H

typedef enum _error_number
    {
        NO_ERROR,
        COULD_NOT_INITIALIZE_SCREEN,
        COULD_NOT_INITIALIZE_INPUT,
    } ErrorNumber;

#endif /* ERROR_H */
