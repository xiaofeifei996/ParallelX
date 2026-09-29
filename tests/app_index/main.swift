import Foundation

for (name, expected) in [("微信", "W"), ("支付宝", "Z"), ("百度网盘", "B"),
                         ("YouTube", "Y"), ("  safari", "S"), ("Éclair", "E"),
                         ("Ａpp", "A"), ("123", "#"), ("🎬", "#"), ("", "#")] {
    precondition(PXAppInitial(name) == expected, "Incorrect index for \(name)")
}
print("App index checks passed")
