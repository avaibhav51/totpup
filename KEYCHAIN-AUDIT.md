# Totpup Keychain operations and recovery

No new Keychain database or background Keychain service was installed. Extra items used the existing login Keychain at `/Users/VaibhavAgarwal/Library/Keychains/login.keychain-db`.

| Service | Account | Data and purpose | Recovery status |
| --- | --- | --- | --- |
| `app.totpup.probe.shared` | `dummy` | Literal `DUMMY-NOT-A-CREDENTIAL`; disposable sharing experiment | Deleted after the experiment; confirmed absent during recovery |
| `app.totpup.widget-code-cache` | `snapshot` | Account labels, current OTPs and expiry times, lock/protection state, reveal duration; never enrollment secrets | Deleted successfully during recovery |
| `app.totpup.authenticator` | `accounts` and account UUIDs | Existing account metadata and enrolled TOTP secrets | Preserved; original vault items |

## Disposable experiment

`/tmp/TotpupKeychainOwner` created one generic-password item with an explicit legacy Keychain access list for that owner binary and `/tmp/TotpupInteractiveProbe`. The dummy literal above was its only data.

`/tmp/TotpupInteractiveProbe --read-probe-keychain` was attempted as a sandboxed widget binary. It exited with status 133 before reporting successful access. This did not establish working widget sharing.

`/tmp/TotpupKeychainOwner --clean` removed the dummy item. These were finite tools, not installed services or scheduled jobs.

## Interactive widget experiment

Totpup 0.2.5 attempted to publish expiring code snapshots into `app.totpup.widget-code-cache` with an explicit access list for its executable and bundled `TotpupWidgets` executable. This changed access only on the separate cache item, not the original account-secret items.

A one-second timer checked whether the snapshot needed updating. Failed writes were not throttled, so an unsuccessful operation could be retried every second. Those operations ran on the main actor and could block app UI or repeat authorization requests. This was a defect; the precise cause of the reported widget hang was not established.

The timer and cache-publication calls were removed in 0.2.6. The shipped widget was restored to a launcher without Security, LocalAuthentication, App Intents, or Keychain access. Experimental source was moved outside compiled targets during recovery and deleted in 0.3.0. No shared-Keychain widget code remains in the project.

## Recovery performed

1. Asked Totpup to quit using AppleScript.
2. Terminated the remaining `TotpupWidgets` process, PID `96643`.
3. Ran `security delete-generic-password -s app.totpup.widget-code-cache -a snapshot`. Deletion succeeded.
4. Ran `security delete-generic-password -s app.totpup.probe.shared -a dummy`. The item was already absent.
5. Rebuilt the recovery app with the writer removed.
6. Registered the restored 0.2.6 launcher extension and restarted Notification Center using `killall NotificationCenter` to recover the stuck widget interface. Totpup was not reopened.

No cleanup command targeted `app.totpup.authenticator`. No enrollment secrets or actual OTP values were printed by cleanup commands.

Keychain items are stored records. Authorization dialogs are requests from processes; stopping Totpup and its extension stops their requests. The system Keychain service itself remains running.
