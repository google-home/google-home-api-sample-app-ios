// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
import SwiftUI

enum AppCornerRadius: CGFloat {
    case xxs = 4
    case xs = 8
    case sm = 12
    case smd = 16
    case md = 18
    case lg = 20
    case xl = 24
    case xxl = 28
}

extension View {

    func cornerRadius(_ radius: AppCornerRadius, antialiased: Bool = true) -> some View {
        self.cornerRadius(radius.rawValue, antialiased: antialiased)
    }

    func presentationCornerRadius(_ cornerRadius: AppCornerRadius?) -> some View {
        self.presentationCornerRadius(cornerRadius?.rawValue)
    }

    func clipShape<S>(_ shape: S, style: FillStyle = FillStyle(), cornerRadius: AppCornerRadius) -> some View where S: Shape {
        self.clipShape(shape, style: style)
            .cornerRadius(cornerRadius.rawValue)
    }
}

extension RoundedRectangle {
    init(cornerRadius: AppCornerRadius, style: RoundedCornerStyle = .circular) {
        self.init(cornerRadius: cornerRadius.rawValue, style: style)
    }
}
