# FujiNet Game Lobby Client

This is a cross-platform version of the Lobby Client, utilizing [FujiNet-Lib](https://github.com/FujiNetWIFI/fujinet-lib).

The goal of the [FujiNet Lobby](http://fujinet.online:8080/) is to make it easy to find and play online games that span multiple platforms.

The Lobby can be started directly from config by pressing **`L`** and displays a real time list of online game servers.

## Supported Systems
* Atari 
* Apple ][
* CoCo 1/2/3 (32KB+)
* C64 (planned)

##  Use
On first run, enter your name. This will be used to identify you in any online game played from the Lobby.

Then pick from a list of available online servers. The Lobby will download and start the game, connecting to the server you chose.

### More Details
The Lobby Client choose the correct disk for the system and mounts/boots/starts the game, after storing the server details in an [AppKey](https://github.com/FujiNetWIFI/fujinet-firmware/wiki/SIO-Command-%24DC-Open-App-Key). 

The game then read the **AppKey** to know which server to connect to, and joins the game.

By design, if your system needs to be reset and you boot the game game, it will auto join the last server it was connected to, via the **AppKey**.

## Lobby Server
Details about implementing a game server or client and working with the Lobby Server can be viewed at http://fujinet.online:8080/docs
