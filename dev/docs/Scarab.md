# Overview of Scarab

* [**user**] - locks `SOUL` for a `recipient`.
* [**user**] - specifies `amount`,  `recipient`, `unlock date`.

* [**recipient**] - unlocks on or after `unlock date`.
* [**recipient**] - pays 10% SOUL amount in SEANCE as a `tribute` to unlock.

* [**outcaster**] - contract that burns SEANCE recieved as a tribute.

> **NOTE**: only an operator may burn **SEANCE**. This is why a `tribute` is sent to the outcaster because a recipient cannot burn nor can every new Scarab contract created.