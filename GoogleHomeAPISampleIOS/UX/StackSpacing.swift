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

enum StackSpacing: CGFloat {
    case xxs = 2
    case xs = 4
    case sm = 8
    case smd = 12
    case mmd = 16
    case md = 20
    case lg = 24
    case xl = 30
}

extension VStack where Content: View {

    init(
        alignment: HorizontalAlignment = .center,
        spacing: StackSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            alignment: alignment,
            spacing: spacing.rawValue,
            content: content
        )
    }
}

extension HStack where Content: View {

    init(
        alignment: VerticalAlignment = .center,
        spacing: StackSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            alignment: alignment,
            spacing: spacing.rawValue,
            content: content
        )
    }
}
