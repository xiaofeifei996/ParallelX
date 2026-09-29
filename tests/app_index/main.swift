import Foundation

for (name, expected) in [("微信", "W"), ("支付宝", "Z"), ("百度网盘", "B"),
                         ("YouTube", "Y"), ("  safari", "S"), ("Éclair", "E"),
                         ("Ａpp", "A"), ("123", "#"), ("🎬", "#"), ("", "#")] {
    precondition(PXAppInitial(name) == expected, "Incorrect index for \(name)")
}
print("App index checks passed")
let railCases: [(CGFloat, CGFloat)] = [(0, 380), (0.5, 330), (1, 380), (-1, 380), (2, 380)]
for (progress, expected) in railCases {
    precondition(abs(PXAppRailX(base: 380, bow: 50, progress: progress) - expected) < 0.001)
}
precondition(abs(PXAppRailX(base: 380, bow: 50, progress: 0.25) - PXAppRailX(base: 380, bow: 50, progress: 0.75)) < 0.001)
print("Curved index geometry checks passed")
for count in [1, 3, 9, 10, 18, 60, 150] {
    let cell = PXAppGridCell(count: count, width: 180, height: 500)
    precondition(cell * 3 <= 180.001)
    precondition(cell * CGFloat((count + 2) / 3) <= 500.001)
}
let portraitCard = CGRect(x: 80, y: 100, width: 300, height: 600)
precondition(PXBottomGestureFrame(card: portraitCard, screen: CGRect(x: 0, y: 0, width: 428, height: 926), width: 300, height: 80, offset: 0) == CGRect(x: 80, y: 700, width: 300, height: 80))
let landscape = CGRect(x: 0, y: 0, width: 926, height: 428)
let swipeArea = PXBottomGestureFrame(card: CGRect(x: 680, y: 40, width: 150, height: 340), screen: landscape, width: 300, height: 80, offset: 0)
precondition(swipeArea.contains(CGPoint(x: landscape.midX, y: landscape.maxY - 16)))
precondition(swipeArea.contains(CGPoint(x: 755, y: 400)))
precondition(landscape.contains(swipeArea))
print("Full grid and landscape swipe-area checks passed")
