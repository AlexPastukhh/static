import java.nio.file.{Files, Paths}
import io.shiftleft.codepropertygraph.generated.Properties
import io.shiftleft.codepropertygraph.generated.nodes.{AstNode, Call, ControlStructure}
import io.shiftleft.semanticcpg.language._

@main def exec(
  cpgFile: String,
  outFile: String
) = {
  val normalizedCpg = cpgFile.replace('\\', '/')
  val normalizedOut = outFile.replace('\\', '/')

  importCpg(normalizedCpg)

  def esc(s: String): String = {
    Option(s).getOrElse("")
      .replace("\\", "\\\\")
      .replace("\"", "\\\"")
      .replace("\r", "\\r")
      .replace("\n", "\\n")
      .replace("\t", "\\t")
  }

  def q(s: String): String =
    "\"" + esc(s) + "\""

  def jsonArray(values: Seq[String]): String =
    values.mkString("[", ",", "]")

  def jsonInt(value: Option[Int]): String =
    value.map(_.toString).getOrElse("null")

  def nodeKind(n: AstNode): String =
    n.getClass.getSimpleName.replace("$", "")

  def safeSourceCode(n: AstNode): String =
    try n.sourceCode
    catch {
      case _: Throwable => n.code
    }

  def nodeIds(root: AstNode): Set[Long] =
    (List(root.id()) ++ root.start.ast.id.l).toSet

  val types =
    cpg.typeDecl.internal.l
      .filter(t =>
        t.name != "ANY" &&
        t.filename != "<unknown>"
      )
      .distinctBy(_.fullName)
      .sortBy(_.fullName)

  val methods =
    cpg.method.internal.l
      .filter(m =>
        m.filename != "<unknown>" &&
        !m.name.startsWith("<operator>")
      )
      .sortBy(m => (m.filename, m.lineNumber.getOrElse(Int.MaxValue), m.fullName))

  val typesJson =
    types.map { t =>
      val bases =
        t.start.baseTypeDecl.fullName.l
          .distinct
          .sorted

      s"""    {
         |      "id": ${t.id()},
         |      "name": ${q(t.name)},
         |      "fullName": ${q(t.fullName)},
         |      "file": ${q(t.filename)},
         |      "inheritsFrom": ${jsonArray(bases.map(q))}
         |    }""".stripMargin
    }.mkString(",\n")

  var totalParameters = 0
  var totalAstNodes = 0
  var totalCalls = 0
  var totalControls = 0
  var totalNestedMethodSubtreesPruned = 0

  val methodsJson =
    methods.map { method =>
      val owner =
        method.start.definingTypeDecl.fullName.headOption
          .getOrElse("")

      val parameters =
        method.start.parameter.l
          .sortBy(p => (p.index, p.order, p.id()))

      val returnType =
        method.start.methodReturn.typeFullName.headOption
          .getOrElse("")

      val fullAstNodes =
        (List(method.asInstanceOf[AstNode]) ++ method.start.ast.l)
          .distinctBy(_.id())

      // Python <module>/<body> and TypeScript :program ASTs contain nested
      // METHOD subtrees. Those nested methods are exported separately below,
      // so do not duplicate their bodies into the enclosing method.
      val nestedMethodRoots =
        fullAstNodes
          .filter(n =>
            n.id() != method.id() &&
            nodeKind(n) == "Method"
          )

      val nestedMethodNodeIds =
        nestedMethodRoots
          .flatMap(nodeIds)
          .toSet

      val astNodes =
        fullAstNodes
          .filterNot(n => nestedMethodNodeIds.contains(n.id()))
          .sortBy { n =>
            (
              n.lineNumber.getOrElse(Int.MaxValue),
              n.columnNumber.getOrElse(Int.MaxValue),
              n.order,
              n.id()
            )
          }

      val localAstNodeIds =
        astNodes.map(_.id()).toSet

      val controls =
        method.start.controlStructure.l
          .filter(cs => localAstNodeIds.contains(cs.id()))
          .sortBy { cs =>
            (
              cs.lineNumber.getOrElse(Int.MaxValue),
              cs.columnNumber.getOrElse(Int.MaxValue),
              cs.order,
              cs.id()
            )
          }

      case class ControlInfo(
        node: ControlStructure,
        conditionRootIds: List[Long],
        conditionNodeIds: Set[Long],
        trueRootIds: List[Long],
        trueNodeIds: Set[Long],
        falseRootIds: List[Long],
        falseNodeIds: Set[Long]
      )

      val controlInfos =
        controls.map { cs =>
          val conditionRoots =
            cs.start.condition.l
              .filter(n => localAstNodeIds.contains(n.id()))

          val conditionIds =
            conditionRoots
              .flatMap(nodeIds)
              .filter(localAstNodeIds.contains)
              .toSet

          val isIf =
            Option(cs.controlStructureType)
              .getOrElse("")
              .equalsIgnoreCase("IF")

          val trueRoots =
            if (isIf) {
              cs.start.whenTrue.l
                .filter(n => localAstNodeIds.contains(n.id()))
            } else {
              Nil
            }

          val falseRoots =
            if (isIf) {
              cs.start.whenFalse.l
                .filter(n => localAstNodeIds.contains(n.id()))
            } else {
              Nil
            }

          ControlInfo(
            node = cs,
            conditionRootIds = conditionRoots.map(_.id()),
            conditionNodeIds = conditionIds,
            trueRootIds = trueRoots.map(_.id()),
            trueNodeIds = trueRoots.flatMap(nodeIds).filter(localAstNodeIds.contains).toSet,
            falseRootIds = falseRoots.map(_.id()),
            falseNodeIds = falseRoots.flatMap(nodeIds).filter(localAstNodeIds.contains).toSet
          )
        }

      val calls =
        method.start.ast.isCall.l
          .filter(c => localAstNodeIds.contains(c.id()))
          .sortBy { c =>
            (
              c.lineNumber.getOrElse(Int.MaxValue),
              c.columnNumber.getOrElse(Int.MaxValue),
              c.order,
              c.id()
            )
          }

      totalParameters += parameters.size
      totalNestedMethodSubtreesPruned += nestedMethodRoots.size
      totalAstNodes += astNodes.size
      totalCalls += calls.size
      totalControls += controls.size

      val parametersJson =
        parameters.map { p =>
          s"""        {
             |          "id": ${p.id()},
             |          "name": ${q(p.name)},
             |          "code": ${q(p.code)},
             |          "typeFullName": ${q(p.typeFullName)},
             |          "index": ${p.index},
             |          "order": ${p.order},
             |          "line": ${jsonInt(p.lineNumber)},
             |          "column": ${jsonInt(p.columnNumber)}
             |        }""".stripMargin
        }.mkString(",\n")

      val astJson =
        astNodes.map { n =>
          val parentIds =
            n.start.astParent.id.l
              .filter(localAstNodeIds.contains)
              .distinct

          val childIds =
            n.start.astChildren.id.l
              .filter(localAstNodeIds.contains)
              .distinct

          val typeFullName =
            n.propertyOption(Properties.TypeFullName)
              .getOrElse("")

          s"""        {
             |          "id": ${n.id()},
             |          "kind": ${q(nodeKind(n))},
             |          "code": ${q(n.code)},
             |          "sourceCode": ${q(safeSourceCode(n))},
             |          "typeFullName": ${q(typeFullName)},
             |          "line": ${jsonInt(n.lineNumber)},
             |          "column": ${jsonInt(n.columnNumber)},
             |          "offset": ${jsonInt(n.offset)},
             |          "offsetEnd": ${jsonInt(n.offsetEnd)},
             |          "order": ${n.order},
             |          "parentIds": ${jsonArray(parentIds.map(_.toString))},
             |          "childIds": ${jsonArray(childIds.map(_.toString))}
             |        }""".stripMargin
        }.mkString(",\n")

      val controlsJson =
        controlInfos.map { info =>
          val cs = info.node

          val localControlIds =
            controls.map(_.id()).toSet

          val parentControlIds =
            cs.start.inAstMinusLeaf.isControlStructure.id.l
              .filter(localControlIds.contains)
              .distinct

          val directChildIds =
            cs.start.astChildren.id.l
              .filter(localAstNodeIds.contains)
              .distinct

          val trueBodyRoots = cs.trueBodyOut.l
          val falseBodyRoots = cs.falseBodyOut.l
          val doBodyRoots = cs.doBodyOut.l
          val forInitRoots = cs.forInitOut.l
          val forUpdateRoots = cs.forUpdateOut.l
          val forBodyRoots = cs.forBodyOut.l
          val tryBodyRoots = cs.tryBodyOut.l
          val catchBodyRoots = cs.catchBodyOut.l
          val finallyBodyRoots = cs.finallyBodyOut.l

          def subtreeIds(roots: Seq[AstNode]): List[Long] =
            roots
              .flatMap(nodeIds)
              .filter(localAstNodeIds.contains)
              .distinct
              .sorted
              .toList

          s"""        {
             |          "id": ${cs.id()},
             |          "kind": ${q(cs.controlStructureType)},
             |          "parserTypeName": ${q(cs.parserTypeName)},
             |          "code": ${q(cs.code)},
             |          "sourceCode": ${q(safeSourceCode(cs))},
             |          "line": ${jsonInt(cs.lineNumber)},
             |          "column": ${jsonInt(cs.columnNumber)},
             |          "offset": ${jsonInt(cs.offset)},
             |          "offsetEnd": ${jsonInt(cs.offsetEnd)},
             |          "order": ${cs.order},
             |          "parentControlIds": ${jsonArray(parentControlIds.map(_.toString))},
             |          "directChildIds": ${jsonArray(directChildIds.map(_.toString))},
             |          "conditionRootIds": ${jsonArray(info.conditionRootIds.map(_.toString))},
             |          "conditionNodeIds": ${jsonArray(info.conditionNodeIds.toList.sorted.map(_.toString))},
             |          "ifTrueRootIds": ${jsonArray(info.trueRootIds.map(_.toString))},
             |          "ifTrueNodeIds": ${jsonArray(info.trueNodeIds.toList.sorted.map(_.toString))},
             |          "ifFalseRootIds": ${jsonArray(info.falseRootIds.map(_.toString))},
             |          "ifFalseNodeIds": ${jsonArray(info.falseNodeIds.toList.sorted.map(_.toString))},
             |          "trueBodyRootIds": ${jsonArray(trueBodyRoots.map(_.id().toString))},
             |          "trueBodyNodeIds": ${jsonArray(subtreeIds(trueBodyRoots).map(_.toString))},
             |          "falseBodyRootIds": ${jsonArray(falseBodyRoots.map(_.id().toString))},
             |          "falseBodyNodeIds": ${jsonArray(subtreeIds(falseBodyRoots).map(_.toString))},
             |          "doBodyRootIds": ${jsonArray(doBodyRoots.map(_.id().toString))},
             |          "doBodyNodeIds": ${jsonArray(subtreeIds(doBodyRoots).map(_.toString))},
             |          "forInitRootIds": ${jsonArray(forInitRoots.map(_.id().toString))},
             |          "forInitNodeIds": ${jsonArray(subtreeIds(forInitRoots).map(_.toString))},
             |          "forUpdateRootIds": ${jsonArray(forUpdateRoots.map(_.id().toString))},
             |          "forUpdateNodeIds": ${jsonArray(subtreeIds(forUpdateRoots).map(_.toString))},
             |          "forBodyRootIds": ${jsonArray(forBodyRoots.map(_.id().toString))},
             |          "forBodyNodeIds": ${jsonArray(subtreeIds(forBodyRoots).map(_.toString))},
             |          "tryBodyRootIds": ${jsonArray(tryBodyRoots.map(_.id().toString))},
             |          "tryBodyNodeIds": ${jsonArray(subtreeIds(tryBodyRoots).map(_.toString))},
             |          "catchBodyRootIds": ${jsonArray(catchBodyRoots.map(_.id().toString))},
             |          "catchBodyNodeIds": ${jsonArray(subtreeIds(catchBodyRoots).map(_.toString))},
             |          "finallyBodyRootIds": ${jsonArray(finallyBodyRoots.map(_.id().toString))},
             |          "finallyBodyNodeIds": ${jsonArray(subtreeIds(finallyBodyRoots).map(_.toString))}
             |        }""".stripMargin
        }.mkString(",\n")

      val callsJson =
        calls.map { c =>
          val possibleTargets =
            c.start.callee.fullName.l
              .distinct
              .sorted

          val arguments =
            c.start.argument.l
              .sortBy(a => (a.argumentIndex, a.order, a.id()))

          val argumentsJson =
            arguments.map { a =>
              s"""            {
                 |              "id": ${a.id()},
                 |              "argumentIndex": ${a.argumentIndex},
                 |              "order": ${a.order},
                 |              "code": ${q(a.code)},
                 |              "typeFullName": ${q(a.propertyOption(Properties.TypeFullName).getOrElse(""))},
                 |              "line": ${jsonInt(a.lineNumber)},
                 |              "column": ${jsonInt(a.columnNumber)},
                 |              "offset": ${jsonInt(a.offset)},
                 |              "offsetEnd": ${jsonInt(a.offsetEnd)}
                 |            }""".stripMargin
            }.mkString(",\n")

          val parentIds =
            c.start.astParent.id.l
              .filter(localAstNodeIds.contains)
              .distinct

          val ancestorCallIds =
            c.start.inAstMinusLeaf.isCall.id.l
              .filter(localAstNodeIds.contains)
              .distinct

          val localControlIds =
            controls.map(_.id()).toSet

          val controlAncestorIds =
            c.start.inAstMinusLeaf.isControlStructure.id.l
              .filter(localControlIds.contains)
              .distinct

          val conditionOf =
            controlInfos
              .filter(_.conditionNodeIds.contains(c.id()))
              .map(_.node.id())

          val ifTrueOf =
            controlInfos
              .filter(_.trueNodeIds.contains(c.id()))
              .map(_.node.id())

          val ifFalseOf =
            controlInfos
              .filter(_.falseNodeIds.contains(c.id()))
              .map(_.node.id())

          val cfgNextIds =
            c.cfgNext.id.l.distinct

          s"""        {
             |          "id": ${c.id()},
             |          "name": ${q(c.name)},
             |          "code": ${q(c.code)},
             |          "sourceCode": ${q(safeSourceCode(c))},
             |          "line": ${jsonInt(c.lineNumber)},
             |          "column": ${jsonInt(c.columnNumber)},
             |          "offset": ${jsonInt(c.offset)},
             |          "offsetEnd": ${jsonInt(c.offsetEnd)},
             |          "order": ${c.order},
             |          "argumentIndex": ${c.argumentIndex},
             |          "typeFullName": ${q(c.typeFullName)},
             |          "signature": ${q(c.signature)},
             |          "dispatchType": ${q(c.dispatchType)},
             |          "methodFullName": ${q(c.methodFullName)},
             |          "isOperator": ${c.name.startsWith("<operator>")},
             |          "possibleTargets": ${jsonArray(possibleTargets.map(q))},
             |          "astParentIds": ${jsonArray(parentIds.map(_.toString))},
             |          "ancestorCallIds": ${jsonArray(ancestorCallIds.map(_.toString))},
             |          "controlAncestorIds": ${jsonArray(controlAncestorIds.map(_.toString))},
             |          "conditionOfControlIds": ${jsonArray(conditionOf.map(_.toString))},
             |          "ifTrueOfControlIds": ${jsonArray(ifTrueOf.map(_.toString))},
             |          "ifFalseOfControlIds": ${jsonArray(ifFalseOf.map(_.toString))},
             |          "cfgNextIds": ${jsonArray(cfgNextIds.map(_.toString))},
             |          "arguments": [
             |$argumentsJson
             |          ]
             |        }""".stripMargin
        }.mkString(",\n")

      s"""    {
         |      "id": ${method.id()},
         |      "name": ${q(method.name)},
         |      "fullName": ${q(method.fullName)},
         |      "signature": ${q(method.signature)},
         |      "owner": ${q(owner)},
         |      "file": ${q(method.filename)},
         |      "line": ${jsonInt(method.lineNumber)},
         |      "column": ${jsonInt(method.columnNumber)},
         |      "offset": ${jsonInt(method.offset)},
         |      "offsetEnd": ${jsonInt(method.offsetEnd)},
         |      "sourceCode": ${q(safeSourceCode(method))},
         |      "returnType": ${q(returnType)},
         |      "parameters": [
         |$parametersJson
         |      ],
         |      "astNodes": [
         |$astJson
         |      ],
         |      "controlStructures": [
         |$controlsJson
         |      ],
         |      "calls": [
         |$callsJson
         |      ]
         |    }""".stripMargin
    }.mkString(",\n")

  val model =
    s"""{
       |  "rawStructuralVersion": 1,
       |  "purpose": "All-method raw Joern structural export for Static Execution Model v4 normalization. This is not the public v4 schema.",
       |  "summary": {
       |    "types": ${types.size},
       |    "methods": ${methods.size},
       |    "parameters": $totalParameters,
       |    "astNodes": $totalAstNodes,
       |    "callsIncludingOperators": $totalCalls,
       |    "controlStructures": $totalControls,
       |    "nestedMethodSubtreesPruned": $totalNestedMethodSubtreesPruned
       |  },
       |  "types": [
       |$typesJson
       |  ],
       |  "methods": [
       |$methodsJson
       |  ]
       |}
       |""".stripMargin

  val out = Paths.get(normalizedOut)
  val parent = out.getParent
  if (parent != null) {
    Files.createDirectories(parent)
  }

  Files.writeString(out, model)

  println()
  println("V4 RAW STRUCTURAL EXPORT COMPLETE")
  println("---------------------------------")
  println(s"Types:              ${types.size}")
  println(s"Methods:            ${methods.size}")
  println(s"Parameters:         $totalParameters")
  println(s"AST nodes:          $totalAstNodes")
  println(s"Calls (+operators): $totalCalls")
  println(s"Controls:           $totalControls")
  println(s"Nested methods cut: $totalNestedMethodSubtreesPruned")
  println()
  println(out)
}
