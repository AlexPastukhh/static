import java.nio.file.{Files, Paths}
import io.shiftleft.codepropertygraph.generated.Properties
import io.shiftleft.codepropertygraph.generated.nodes.{AstNode, CfgNode, Call, ControlStructure}
import io.shiftleft.semanticcpg.language._

@main def exec(
  cpgFile: String,
  outFile: String,
  methodName: String,
  ownerContains: String
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

  def jsonLong(value: Option[Long]): String =
    value.map(_.toString).getOrElse("null")

  def jsonInt(value: Option[Int]): String =
    value.map(_.toString).getOrElse("null")

  def nodeKind(n: AstNode): String =
    n.getClass.getSimpleName.replace("$", "")

  def cfgNodeKind(n: CfgNode): String =
    n.getClass.getSimpleName.replace("$", "")

  def safeSourceCode(n: AstNode): String =
    try n.sourceCode
    catch {
      case _: Throwable => n.code
    }

  def nodeIds(root: AstNode): Set[Long] = {
    (List(root.id()) ++ root.start.ast.id.l).toSet
  }

  val candidateMethods =
    cpg.method.internal.l
      .filter(_.name == methodName)
      .map { m =>
        val owner =
          m.start.definingTypeDecl.fullName.headOption
            .getOrElse("")
        (m, owner)
      }
      .filter { case (_, owner) =>
        ownerContains.isEmpty || owner.contains(ownerContains)
      }

  if (candidateMethods.isEmpty) {
    val sameName =
      cpg.method.internal.l
        .filter(_.name == methodName)
        .map { m =>
          val owner =
            m.start.definingTypeDecl.fullName.headOption
              .getOrElse("")
          s"${m.fullName} | owner=$owner | file=${m.filename}"
        }
        .sorted

    throw new RuntimeException(
      s"""Target method was not found.
         |methodName=$methodName
         |ownerContains=$ownerContains
         |Same-name candidates:
         |${sameName.mkString("\n")}
         |""".stripMargin
    )
  }

  if (candidateMethods.size > 1) {
    val rows =
      candidateMethods.map { case (m, owner) =>
        s"${m.fullName} | owner=$owner | file=${m.filename}"
      }.sorted

    throw new RuntimeException(
      s"""Target method is ambiguous.
         |methodName=$methodName
         |ownerContains=$ownerContains
         |Candidates:
         |${rows.mkString("\n")}
         |""".stripMargin
    )
  }

  val (method, owner) = candidateMethods.head

  val astNodes =
    (List(method.asInstanceOf[AstNode]) ++ method.start.ast.l)
      .distinctBy(_.id())
      .sortBy { n =>
        (
          n.lineNumber.getOrElse(Int.MaxValue),
          n.columnNumber.getOrElse(Int.MaxValue),
          n.order,
          n.id()
        )
      }

  val controls =
    method.start.controlStructure.l
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
      val conditionRoots = cs.start.condition.l
      val conditionIds = conditionRoots.flatMap(nodeIds).toSet

      val isIf =
        Option(cs.controlStructureType)
          .getOrElse("")
          .equalsIgnoreCase("IF")

      val trueRoots =
        if (isIf) cs.start.whenTrue.l
        else Nil

      val falseRoots =
        if (isIf) cs.start.whenFalse.l
        else Nil

      ControlInfo(
        node = cs,
        conditionRootIds = conditionRoots.map(_.id()),
        conditionNodeIds = conditionIds,
        trueRootIds = trueRoots.map(_.id()),
        trueNodeIds = trueRoots.flatMap(nodeIds).toSet,
        falseRootIds = falseRoots.map(_.id()),
        falseNodeIds = falseRoots.flatMap(nodeIds).toSet
      )
    }

  val calls =
    method.start.ast.isCall.l
      .sortBy { c =>
        (
          c.lineNumber.getOrElse(Int.MaxValue),
          c.columnNumber.getOrElse(Int.MaxValue),
          c.order,
          c.id()
        )
      }

  val parameters =
    method.start.parameter.l
      .sortBy(_.index)

  val returnType =
    method.start.methodReturn.typeFullName.headOption
      .getOrElse("")

  val cfgNodes =
    method.start.cfgNode.l
      .distinctBy(_.id())
      .sortBy { n =>
        (
          n.lineNumber.getOrElse(Int.MaxValue),
          n.columnNumber.getOrElse(Int.MaxValue),
          n.order,
          n.id()
        )
      }

  val cfgNodeIds = cfgNodes.map(_.id()).toSet

  val cfgEdges =
    cfgNodes.flatMap { from =>
      from.cfgNext.l.map { to =>
        (from.id(), to.id(), cfgNodeIds.contains(to.id()))
      }
    }.distinct
      .sortBy { case (fromId, toId, _) => (fromId, toId) }

  val parametersJson =
    parameters.map { p =>
      s"""    {
         |      "id": ${p.id()},
         |      "name": ${q(p.name)},
         |      "code": ${q(p.code)},
         |      "typeFullName": ${q(p.typeFullName)},
         |      "index": ${p.index},
         |      "order": ${p.order},
         |      "line": ${jsonInt(p.lineNumber)},
         |      "column": ${jsonInt(p.columnNumber)}
         |    }""".stripMargin
    }.mkString(",\n")

  val astJson =
    astNodes.map { n =>
      val parentIds =
        n.start.astParent.id.l.distinct

      val childIds =
        n.start.astChildren.id.l.distinct

      s"""    {
         |      "id": ${n.id()},
         |      "kind": ${q(nodeKind(n))},
         |      "code": ${q(n.code)},
         |      "sourceCode": ${q(safeSourceCode(n))},
         |      "line": ${jsonInt(n.lineNumber)},
         |      "column": ${jsonInt(n.columnNumber)},
         |      "offset": ${jsonInt(n.offset)},
         |      "offsetEnd": ${jsonInt(n.offsetEnd)},
         |      "order": ${n.order},
         |      "parentIds": ${jsonArray(parentIds.map(_.toString))},
         |      "childIds": ${jsonArray(childIds.map(_.toString))}
         |    }""".stripMargin
    }.mkString(",\n")

  val controlsJson =
    controlInfos.map { info =>
      val cs = info.node

      val parentControlIds =
        cs.start.inAstMinusLeaf.isControlStructure.id.l.distinct

      val directChildIds =
        cs.start.astChildren.id.l.distinct

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
        roots.flatMap(nodeIds).distinct.sorted.toList

      s"""    {
         |      "id": ${cs.id()},
         |      "kind": ${q(cs.controlStructureType)},
         |      "parserTypeName": ${q(cs.parserTypeName)},
         |      "code": ${q(cs.code)},
         |      "sourceCode": ${q(safeSourceCode(cs))},
         |      "line": ${jsonInt(cs.lineNumber)},
         |      "column": ${jsonInt(cs.columnNumber)},
         |      "offset": ${jsonInt(cs.offset)},
         |      "offsetEnd": ${jsonInt(cs.offsetEnd)},
         |      "order": ${cs.order},
         |      "parentControlIds": ${jsonArray(parentControlIds.map(_.toString))},
         |      "directChildIds": ${jsonArray(directChildIds.map(_.toString))},
         |      "conditionRootIds": ${jsonArray(info.conditionRootIds.map(_.toString))},
         |      "conditionNodeIds": ${jsonArray(info.conditionNodeIds.toList.sorted.map(_.toString))},
         |      "ifTrueRootIds": ${jsonArray(info.trueRootIds.map(_.toString))},
         |      "ifTrueNodeIds": ${jsonArray(info.trueNodeIds.toList.sorted.map(_.toString))},
         |      "ifFalseRootIds": ${jsonArray(info.falseRootIds.map(_.toString))},
         |      "ifFalseNodeIds": ${jsonArray(info.falseNodeIds.toList.sorted.map(_.toString))},
         |      "trueBodyRootIds": ${jsonArray(trueBodyRoots.map(_.id().toString))},
         |      "trueBodyNodeIds": ${jsonArray(subtreeIds(trueBodyRoots).map(_.toString))},
         |      "falseBodyRootIds": ${jsonArray(falseBodyRoots.map(_.id().toString))},
         |      "falseBodyNodeIds": ${jsonArray(subtreeIds(falseBodyRoots).map(_.toString))},
         |      "doBodyRootIds": ${jsonArray(doBodyRoots.map(_.id().toString))},
         |      "doBodyNodeIds": ${jsonArray(subtreeIds(doBodyRoots).map(_.toString))},
         |      "forInitRootIds": ${jsonArray(forInitRoots.map(_.id().toString))},
         |      "forInitNodeIds": ${jsonArray(subtreeIds(forInitRoots).map(_.toString))},
         |      "forUpdateRootIds": ${jsonArray(forUpdateRoots.map(_.id().toString))},
         |      "forUpdateNodeIds": ${jsonArray(subtreeIds(forUpdateRoots).map(_.toString))},
         |      "forBodyRootIds": ${jsonArray(forBodyRoots.map(_.id().toString))},
         |      "forBodyNodeIds": ${jsonArray(subtreeIds(forBodyRoots).map(_.toString))},
         |      "tryBodyRootIds": ${jsonArray(tryBodyRoots.map(_.id().toString))},
         |      "tryBodyNodeIds": ${jsonArray(subtreeIds(tryBodyRoots).map(_.toString))},
         |      "catchBodyRootIds": ${jsonArray(catchBodyRoots.map(_.id().toString))},
         |      "catchBodyNodeIds": ${jsonArray(subtreeIds(catchBodyRoots).map(_.toString))},
         |      "finallyBodyRootIds": ${jsonArray(finallyBodyRoots.map(_.id().toString))},
         |      "finallyBodyNodeIds": ${jsonArray(subtreeIds(finallyBodyRoots).map(_.toString))}
         |    }""".stripMargin
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
          s"""        {
             |          "id": ${a.id()},
             |          "argumentIndex": ${a.argumentIndex},
             |          "order": ${a.order},
             |          "code": ${q(a.code)},
             |          "typeFullName": ${q(a.propertyOption(Properties.TypeFullName).getOrElse(""))},
             |          "line": ${jsonInt(a.lineNumber)},
             |          "column": ${jsonInt(a.columnNumber)},
             |          "offset": ${jsonInt(a.offset)},
             |          "offsetEnd": ${jsonInt(a.offsetEnd)}
             |        }""".stripMargin
        }.mkString(",\n")

      val parentIds =
        c.start.astParent.id.l.distinct

      val ancestorCallIds =
        c.start.inAstMinusLeaf.isCall.id.l.distinct

      val controlAncestorIds =
        c.start.inAstMinusLeaf.isControlStructure.id.l.distinct

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

      s"""    {
         |      "id": ${c.id()},
         |      "name": ${q(c.name)},
         |      "code": ${q(c.code)},
         |      "sourceCode": ${q(safeSourceCode(c))},
         |      "line": ${jsonInt(c.lineNumber)},
         |      "column": ${jsonInt(c.columnNumber)},
         |      "offset": ${jsonInt(c.offset)},
         |      "offsetEnd": ${jsonInt(c.offsetEnd)},
         |      "order": ${c.order},
         |      "argumentIndex": ${c.argumentIndex},
         |      "typeFullName": ${q(c.typeFullName)},
         |      "signature": ${q(c.signature)},
         |      "dispatchType": ${q(c.dispatchType)},
         |      "methodFullName": ${q(c.methodFullName)},
         |      "isOperator": ${c.name.startsWith("<operator>")},
         |      "possibleTargets": ${jsonArray(possibleTargets.map(q))},
         |      "astParentIds": ${jsonArray(parentIds.map(_.toString))},
         |      "ancestorCallIds": ${jsonArray(ancestorCallIds.map(_.toString))},
         |      "controlAncestorIds": ${jsonArray(controlAncestorIds.map(_.toString))},
         |      "conditionOfControlIds": ${jsonArray(conditionOf.map(_.toString))},
         |      "ifTrueOfControlIds": ${jsonArray(ifTrueOf.map(_.toString))},
         |      "ifFalseOfControlIds": ${jsonArray(ifFalseOf.map(_.toString))},
         |      "cfgNextIds": ${jsonArray(cfgNextIds.map(_.toString))},
         |      "arguments": [
         |$argumentsJson
         |      ]
         |    }""".stripMargin
    }.mkString(",\n")

  val cfgNodesJson =
    cfgNodes.map { n =>
      s"""    {
         |      "id": ${n.id()},
         |      "kind": ${q(cfgNodeKind(n))},
         |      "code": ${q(n.code)},
         |      "line": ${jsonInt(n.lineNumber)},
         |      "column": ${jsonInt(n.columnNumber)},
         |      "order": ${n.order}
         |    }""".stripMargin
    }.mkString(",\n")

  val cfgEdgesJson =
    cfgEdges.map { case (fromId, toId, targetInsideMethodCfg) =>
      s"""    {
         |      "from": $fromId,
         |      "to": $toId,
         |      "targetInsideMethodCfg": $targetInsideMethodCfg
         |    }""".stripMargin
    }.mkString(",\n")

  val model =
    s"""{
       |  "probeVersion": 3,
       |  "purpose": "Raw Joern structural probe v3. Typed control-body relations, offsets and sourceCode included. This is not schema v4.",
       |  "method": {
       |    "id": ${method.id()},
       |    "name": ${q(method.name)},
       |    "fullName": ${q(method.fullName)},
       |    "signature": ${q(method.signature)},
       |    "owner": ${q(owner)},
       |    "file": ${q(method.filename)},
       |    "line": ${jsonInt(method.lineNumber)},
       |    "column": ${jsonInt(method.columnNumber)},
       |    "offset": ${jsonInt(method.offset)},
       |    "offsetEnd": ${jsonInt(method.offsetEnd)},
       |    "sourceCode": ${q(safeSourceCode(method))},
       |    "returnType": ${q(returnType)}
       |  },
       |  "summary": {
       |    "parameters": ${parameters.size},
       |    "astNodes": ${astNodes.size},
       |    "callsIncludingOperators": ${calls.size},
       |    "controlStructures": ${controls.size},
       |    "cfgNodes": ${cfgNodes.size},
       |    "cfgEdges": ${cfgEdges.size}
       |  },
       |  "parameters": [
       |$parametersJson
       |  ],
       |  "astNodes": [
       |$astJson
       |  ],
       |  "controlStructures": [
       |$controlsJson
       |  ],
       |  "calls": [
       |$callsJson
       |  ],
       |  "cfgNodes": [
       |$cfgNodesJson
       |  ],
       |  "cfgEdges": [
       |$cfgEdgesJson
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
  println("STRUCTURAL PROBE COMPLETE")
  println("-------------------------")
  println(s"Method:             ${method.fullName}")
  println(s"Owner:              $owner")
  println(s"AST nodes:          ${astNodes.size}")
  println(s"Calls (+operators): ${calls.size}")
  println(s"Controls:           ${controls.size}")
  println(s"CFG nodes:          ${cfgNodes.size}")
  println(s"CFG edges:          ${cfgEdges.size}")
  println()
  println(out)
}
