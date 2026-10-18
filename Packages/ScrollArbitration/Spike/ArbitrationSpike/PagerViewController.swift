import UIKit
import SwiftUI
import ScrollArbitration

final class PagerViewController: UIViewController, UIScrollViewDelegate {
    private let recorder = SequenceRecorder()
    private lazy var scrollView = ArbitratedPagingScrollView(recorder: recorder)
    private var hostings: [UIHostingController<AnyView>] = []
    private var arbiters: [ReferenceScrollArbiter] = []
    private let pageIndexLabel = UILabel()
    private let countLabel = UILabel()
    private let lastLabel = UILabel()
    private let lineHost = UIView()
    private let clearButton = UIButton(type: .system)
    private var lineLabels: [UILabel] = []

    private var currentPage: Int { max(0, min(2, Int((scrollView.contentOffset.x / max(1, scrollView.bounds.width)).rounded()))) }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        for i in 0..<3 {
            let arbiter = ReferenceScrollArbiter(pagingAxis: .horizontal, directionTolerance: 30,
                                                 coordinateSpaceName: "ScrollArbitration.page")
            arbiters.append(arbiter)
            let root = StandInPage(index: i, arbiter: arbiter, recorder: recorder)
                .environment(\.scrollArbiter, arbiter)
            let host = UIHostingController(rootView: AnyView(root))
            host.view.backgroundColor = [UIColor.systemYellow, .systemTeal, .systemPink][i].withAlphaComponent(0.2)
            addChild(host)
            scrollView.addSubview(host.view)
            host.didMove(toParent: self)
            hostings.append(host)
        }
        recorder.arbiters = arbiters
        recorder.onChange = { [weak self] in self?.refreshLog() }

        scrollView.isPagingEnabled = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = true
        scrollView.delegate = self
        scrollView.pageViews = hostings.map(\.view)
        scrollView.arbiters = arbiters
        scrollView.pageIndex = { [weak self] in self?.currentPage ?? 0 }
        scrollView.accessibilityIdentifier = "pager"
        view.addSubview(scrollView)

        for (label, id) in [(pageIndexLabel, "pageIndex"), (countLabel, "log.count"), (lastLabel, "log.last")] {
            label.accessibilityIdentifier = id
            label.isAccessibilityElement = true
            label.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
            label.numberOfLines = 3
            view.addSubview(label)
        }
        lineHost.isUserInteractionEnabled = false
        view.addSubview(lineHost)
        clearButton.setTitle("clear", for: .normal)
        clearButton.accessibilityIdentifier = "log.clear"
        clearButton.addTarget(self, action: #selector(clearLog), for: .touchUpInside)
        view.addSubview(clearButton)
        refreshLog()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let footer: CGFloat = 80
        let pagerFrame = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: safe.height - footer)
        if scrollView.frame != pagerFrame {
            let index = currentPage
            scrollView.frame = pagerFrame
            scrollView.contentSize = CGSize(width: pagerFrame.width * 3, height: pagerFrame.height)
            for (i, h) in hostings.enumerated() {
                h.view.frame = CGRect(x: CGFloat(i) * pagerFrame.width, y: 0, width: pagerFrame.width, height: pagerFrame.height)
            }
            scrollView.contentOffset = CGPoint(x: CGFloat(index) * pagerFrame.width, y: 0)
        }
        let y = pagerFrame.maxY
        pageIndexLabel.frame = CGRect(x: safe.minX + 4, y: y, width: 60, height: 14)
        countLabel.frame = CGRect(x: safe.minX + 70, y: y, width: 60, height: 14)
        clearButton.frame = CGRect(x: safe.maxX - 70, y: y - 4, width: 60, height: 24)
        lastLabel.frame = CGRect(x: safe.minX + 4, y: y + 16, width: safe.width - 8, height: 50)
        lineHost.frame = CGRect(x: safe.minX, y: y + 66, width: 1, height: 1)
    }

    @objc private func clearLog() {
        recorder.clear()
    }

    private func refreshLog() {
        pageIndexLabel.text = "\(currentPage)"
        pageIndexLabel.accessibilityLabel = "\(currentPage)"
        let records = recorder.records
        countLabel.text = "\(records.count)"
        countLabel.accessibilityLabel = "\(records.count)"
        let last = records.last.map(recorder.line) ?? ""
        lastLabel.text = last
        lastLabel.accessibilityLabel = last
        while lineLabels.count < records.count {
            let l = UILabel(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            l.isAccessibilityElement = true
            l.accessibilityIdentifier = "log.\(lineLabels.count + 1)"
            lineHost.addSubview(l)
            lineLabels.append(l)
        }
        for (i, l) in lineLabels.enumerated() {
            l.accessibilityLabel = i < records.count ? recorder.line(records[i]) : ""
            l.isHidden = i >= records.count
        }
    }

    // MARK: delegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        recorder.mutate { r in
            if scrollView.isDragging || scrollView.isDecelerating { r.pagerMoved = true }
            r.pageAfter = self.currentPage
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        recorder.mutate { $0.pageAfter = self.currentPage }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        recorder.mutate { $0.pageAfter = self.currentPage }
    }
}
