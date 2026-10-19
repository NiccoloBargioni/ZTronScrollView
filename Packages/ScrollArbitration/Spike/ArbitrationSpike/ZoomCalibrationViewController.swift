import UIKit

/// `-zoomCal`: native `UIScrollView` zoom animations (`setZoomScale(_:animated:)`, `zoom(to:animated:)`) sampled on every
/// frame for the ZTronScrollView calibration (docs/design/PHYSICS-calibration.md, "Programmatic zoom"). UIKit lives in
/// this spike app only (CLAUDE.md). Same geometry as the demo's ZoomScreen: viewport 300 × 360, content 600 × 600,
/// zoom 1 … 8. Each run writes `Documents/cal/native-zoom-<case>.json`:
/// samples = [[t, modelScale, presentationScale, modelOffsetX, modelOffsetY, presentationOffsetX, presentationOffsetY]]
/// (t = CACurrentMediaTime), events = [[t, name, scale]] from the delegate.
final class ZoomCalibrationViewController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let zoomView = UIView()
    private let info = UILabel()
    private var link: CADisplayLink?
    private var samples: [[Double]] = []
    private var events: [[Any]] = []
    private var gesture = "none"
    private var startedAt: Double = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scrollView.frame = CGRect(x: (view.bounds.width - 300) / 2, y: 140, width: 300, height: 360)
        scrollView.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        scrollView.contentSize = CGSize(width: 600, height: 600)
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 8
        scrollView.bouncesZoom = true
        scrollView.delegate = self
        scrollView.layer.borderColor = UIColor.gray.cgColor
        scrollView.layer.borderWidth = 1
        scrollView.accessibilityIdentifier = "zoomcal.scroller"
        zoomView.frame = CGRect(x: 0, y: 0, width: 600, height: 600)
        for r in 0..<12 {
            for c in 0..<12 {
                let cell = UIView(frame: CGRect(x: c * 50, y: r * 50, width: 50, height: 50))
                cell.backgroundColor = (r + c) % 2 == 0 ? UIColor.systemBlue.withAlphaComponent(0.15)
                                                        : UIColor.systemGreen.withAlphaComponent(0.15)
                zoomView.addSubview(cell)
            }
        }
        scrollView.addSubview(zoomView)
        view.addSubview(scrollView)

        let names = ["set125", "set15", "set2", "set3", "set4", "set8", "rect8", "back", "reset", "save"]
        let stack = UIStackView(arrangedSubviews: names.map { name in
            let b = UIButton(type: .system)
            b.setTitle(name, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 11)
            b.accessibilityIdentifier = "zoomcal.\(name)"
            b.addAction(UIAction { [weak self] _ in self?.perform(name) }, for: .touchUpInside)
            return b
        })
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.frame = CGRect(x: 8, y: 60, width: view.bounds.width - 16, height: 36)
        stack.autoresizingMask = [.flexibleWidth]
        view.addSubview(stack)

        info.frame = CGRect(x: 8, y: 100, width: view.bounds.width - 16, height: 32)
        info.font = .systemFont(ofSize: 11)
        info.numberOfLines = 2
        info.accessibilityIdentifier = "zoomcal.info"
        info.autoresizingMask = [.flexibleWidth]
        view.addSubview(info)
        setInfo("ready")
    }

    private func setInfo(_ text: String) {
        info.text = text
        info.accessibilityValue = text
    }

    private func perform(_ name: String) {
        let from = fmt(scrollView.zoomScale)
        switch name {
        case "set125": begin("set125-from-\(from)"); scrollView.setZoomScale(1.25, animated: true)
        case "set15": begin("set15-from-\(from)"); scrollView.setZoomScale(1.5, animated: true)
        case "set2": begin("set2-from-\(from)"); scrollView.setZoomScale(2, animated: true)
        case "set3": begin("set3-from-\(from)"); scrollView.setZoomScale(3, animated: true)
        case "set4": begin("set4-from-\(from)"); scrollView.setZoomScale(4, animated: true)
        case "set8": begin("set8-from-\(from)"); scrollView.setZoomScale(8, animated: true)
        case "rect8":
            // The demo's double tap: 8x around the content point (300, 322.5) = viewport / 8 centred there.
            begin("rect8-from-\(from)")
            let size = CGSize(width: 300 / 8, height: 360 / 8)
            scrollView.zoom(to: CGRect(x: 300 - size.width / 2, y: 322.5 - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
        case "back":
            begin("back-from-\(from)")
            scrollView.setZoomScale(1, animated: true)
        case "reset":
            stopLink()
            scrollView.setZoomScale(1, animated: false)
            scrollView.contentOffset = .zero
            setInfo("reset z=\(scrollView.zoomScale)")
        case "save": setInfo(save())
        default: break
        }
    }

    private func fmt(_ z: CGFloat) -> String {
        let r = (z * 100).rounded() / 100
        return r == r.rounded() ? "\(Int(r))" : String(format: "%.2f", r).replacingOccurrences(of: ".", with: "p")
    }

    private func begin(_ name: String) {
        gesture = name
        samples = []
        events = []
        startedAt = CACurrentMediaTime()
        record()
        if link == nil {
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
        }
        setInfo("running \(name)")
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick() {
        record()
        // Stop by itself 3 s after the start: everything native does is long over.
        if CACurrentMediaTime() - startedAt > 3 { stopLink() }
    }

    private func record() {
        let t = CACurrentMediaTime()
        let model = Double(scrollView.zoomScale)
        var presentationScale = model
        if let p = zoomView.layer.presentation() {
            let m = p.transform
            presentationScale = Double((m.m11 * m.m11 + m.m12 * m.m12).squareRoot())
        }
        let o = scrollView.contentOffset
        var po = o
        if let p = scrollView.layer.presentation() { po = p.bounds.origin }   // contentOffset is the bounds origin
        samples.append([t, model, presentationScale, Double(o.x), Double(o.y), Double(po.x), Double(po.y)])
    }

    private func save() -> String {
        stopLink()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let dict: [String: Any] = [
            "variant": "native-zoom", "gesture": gesture,
            "os": "\(os.majorVersion).\(os.minorVersion)",
            "viewport": [300.0, 360.0], "content": [600.0, 600.0], "limits": [1.0, 8.0],
            "samples": samples, "events": events,
        ]
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("cal")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("native-zoom-\(gesture).json")
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) {
            try? data.write(to: url)
        }
        return "\(url.lastPathComponent) n=\(samples.count) e=\(events.count) z=\(scrollView.zoomScale)"
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { zoomView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        events.append([CACurrentMediaTime(), "didZoom", Double(scrollView.zoomScale)])
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        events.append([CACurrentMediaTime(), "didEndZooming", Double(scale)])
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        events.append([CACurrentMediaTime(), "didEndScrollingAnimation", Double(scrollView.zoomScale)])
    }
}
