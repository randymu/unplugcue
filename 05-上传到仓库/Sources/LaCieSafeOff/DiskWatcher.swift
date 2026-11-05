// Copyright (c) 2026 randymu
// Licensed under the UnplugCue Free Use and Non-Sale License 1.0.
import DiskArbitration
import Foundation

@MainActor
final class DiskWatcher {
    private var session: DASession?
    private let changed: @MainActor () -> Void

    init(changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
        self.session = session
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, { _, context in
            MainActor.assumeIsolated {
                guard let context else { return }
                Unmanaged<DiskWatcher>.fromOpaque(context).takeUnretainedValue().changed()
            }
        }, context)
        DARegisterDiskDisappearedCallback(session, nil, { _, context in
            MainActor.assumeIsolated {
                guard let context else { return }
                Unmanaged<DiskWatcher>.fromOpaque(context).takeUnretainedValue().changed()
            }
        }, context)
        DARegisterDiskDescriptionChangedCallback(session, nil, nil, { _, _, context in
            MainActor.assumeIsolated {
                guard let context else { return }
                Unmanaged<DiskWatcher>.fromOpaque(context).takeUnretainedValue().changed()
            }
        }, context)
        DASessionSetDispatchQueue(session, .main)
    }

    isolated deinit {
        if let session { DASessionSetDispatchQueue(session, nil) }
    }
}
