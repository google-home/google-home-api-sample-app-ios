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

import GoogleHomeSDK

/// UI level data model that represents an Automation instance.
public struct AutomationUIDataModel {
  /// Name of the automation.
  public let name: String

  /// Automation description.
  public let description: String

  /// Array of strings describing each starter the automation has.
  /// Example: ["device.name Trait", "structure.name Event"]
  public let starters: [String]

  /// Array of strings describing each condition the automation has.
  /// Example: ["property from device.name trait equals value"]
  public let conditions: [String]

  /// Array of strings describing each action the automation has.
  /// Example: ["device.name Command"]
  public let actions: [String]

  /// Creates `AutomationUIDataModel` with `DraftAutomation`.
  /// Takes name and description from it, then flattens the nodes by getting them from flows.
  /// Then filters nodes by their types (Starters, Condition, Actions) into separate arrays.
  /// Each filtered array is converted into an array of strings that describes each node.
  public init(draftAutomation: any DraftAutomation) {
    self.name = draftAutomation.name
    self.description = draftAutomation.description

    if let automationFlow = draftAutomation.automationGraph {
      let allNodes = Self.flattenNodes(from: automationFlow)
      let allStarters = allNodes.compactMap { $0 as? any Starter }
      self.starters = Self.convert(starters: allStarters)
      let allConditions = allNodes.compactMap { $0 as? Condition }
      self.conditions = Self.convert(conditions: allConditions)
      let allActions = allNodes.compactMap { $0 as? Action }
      self.actions = Self.convert(actions: allActions)
    } else {
      self.starters = []
      self.conditions = []
      self.actions = []
    }
  }

  /// Flattens the nodes by getting them from flows.
  ///
  /// Example: Sequential { starter, condition, parallel {action1, action2} } is converted
  /// into [starter, condition, action1, action2].
  private static func flattenNodes(from flow: any Flow) -> [any Node] {
    flow.nodes.flatMap { node in
      if let subflow = node as? any Flow {
        return flattenNodes(from: subflow)
      } else {
        return [node]
      }
    }
  }

  /// Converts array of starters into an array of strings, each describing each starter.
  private static func convert(starters: [any Starter]) -> [String] {
    starters.compactMap { convert(starter: $0) }
  }

  /// Converts any Starter into string that describes it
  ///
  /// Example 1: starter(tv, GoogleTVDeviceType.self, MediaPlaybackTrait.self) is converted into
  /// "tv.name MediaPlaybackTrait".
  /// Example 2: starter(structure, Google.VoiceStarterTrait.OkGoogleEvent.self) is converted into
  /// "structure.name OkGoogleEvent".
  private static func convert(starter: any Starter) -> String {
    var result = ""
    if let device = starter.entity as? HomeDevice {
      result += device.name
    } else if let structure = starter.entity as? Structure {
      result += structure.name
    }
    if let attributeStarter = starter as? AttributeStarter {
      result += " " + String(describing: attributeStarter.trait)
    } else if let eventStarter = starter as? EventStarter {
      result += " " + String(describing: eventStarter.event)
    }
    return result
  }
  /// Converts StateReader into string that describes it.
  ///
  /// Example: stateReader(structure, Google.TimeTrait.self) is converted into
  /// "structure.name TimeTrait".
  private static func convert(stateReader: StateReader) -> String {
    var result = ""
    if let device = stateReader.entity as? HomeDevice {
      result += device.name
    } else if let structure = stateReader.entity as? Structure {
      result += structure.name
    }
    result += " " + String(describing: stateReader.trait)
    return result
  }

  /// Converts array of conditions into an array of strings, each describing each condition.
  private static func convert(conditions: [Condition]) -> [String] {
    conditions.compactMap { return convert(expression: $0.expression) }
  }

  /// Converts Expressions into string that describes it.
  ///
  /// Example: MediaPlaybackTraitStarter.currentState.equals(.paused) is converted into
  /// "currentState from deviceName MediaPlaybackTrait equals paused"
  private static func convert(expression: any Expression) -> String {
    switch expression {
    case let expression as Reference:
      switch expression.referenceValue {
      case .declaration(let declaration):
        return declaration.variable
      case .node(let node):
        if let starter = node as? any Starter {
          return convert(starter: starter)
        } else if let stateReader = node as? StateReader {
          return convert(stateReader: stateReader)
        } else {
          return "unknown node"
        }
      default: return "unknown node"
      }
    case let expression as Constant:
      if let value = "\(expression.value)".extractedPropertyName {
        return "\(value)"
      } else {
        return "unknown value"
      }
    case let expression as FieldSelect:
      if let selected = "\(expression.selected)".extractedPropertyName {
        return "\(selected) from \(convert(expression: expression.from))"
      } else {
        return "unknown field from \(convert(expression: expression.from))"
      }
    case let expression as ListGet:
      return
        "\(convert(expression: expression.index)) in \(convert(expression: expression.listExpression))"
    case let expression as any BinaryExpression:
      return
        "\(convert(expression: expression.operand1)) \(expression.operatorString) \(convert(expression: expression.operand2))"
    case let expression as any TernaryExpression:
      return
        "\(convert(expression: expression.operand1)) \(expression.operatorString) \(convert(expression: expression.operand2)) and \(convert(expression: expression.operand3))"
    default:
      return "unknown expression"
    }
  }

  /// Converts array of actions into an array of strings, each describing each action.
  private static func convert(actions: [Action]) -> [String] {
    actions.compactMap { convert(action: $0) }
  }

  /// Converts Action into string that describes it.
  ///
  /// Example: action(device, WindowCoveringDeviceType.self) { WindowCoveringTrait.downOrClose() } is converted into
  /// "device.name DownOrCloseCommand".
  private static func convert(action: Action) -> String? {
    guard let command = action.behavior as? AutomationCommand else {
      return nil
    }
    if let device = action.entity as? HomeDevice {
      return "\(device.name) \(command.command)"
    } else if let structure = action.entity as? Structure {
      return "\(structure.name) \(command.command)"
    } else {
      return "\(command.command)"
    }
  }
}

extension Expression {
  fileprivate var operatorString: String {
    switch self {
    case is Equals:
      return "equals"
    case is NotEquals:
      return "not equals"
    case is And:
      return "and"
    case is Or:
      return "or"
    case is GreaterThan:
      return "greater than"
    case is GreaterThanOrEquals:
      return "greater than or equals"
    case is LessThan:
      return "less than"
    case is LessThanOrEquals:
      return "less than or equals"
    case is Between:
      return "between"
    case is BetweenTimes:
      return "between"
    default:
      return ""
    }
  }
}

extension String {
  /// Used to receive property name or value from from full object string description.
  ///
  /// Example: [GoogleHomeSDK.AnyField(field: GoogleHomeTypes.Matter.MediaPlaybackTrait.Attribute.currentState)]
  /// is conveted into "currentState"
  fileprivate var extractedPropertyName: SubSequence? {
    self.split { [".", "(", ")", "[", "]"].contains($0) }.last
  }
}
