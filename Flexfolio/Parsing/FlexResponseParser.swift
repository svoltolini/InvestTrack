import Foundation

/// Event-driven parser for both Flex documents: the attribute-based
/// `<FlexQueryResponse>` statement and the element-text-based
/// `<FlexStatementResponse>` service reply. Attributes only for the statement;
/// elements may arrive in any order; unknown elements/attributes are ignored;
/// empty attribute strings mean nil. Rows missing essential fields are skipped
/// rather than failing the whole document.
final class FlexResponseParser: NSObject, XMLParserDelegate {
    static func parse(_ data: Data) throws -> FlexParseResult {
        let delegate = FlexResponseParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() || delegate.rootElement != nil else {
            throw FlexError.badResponse
        }
        switch delegate.rootElement {
        case "FlexQueryResponse":
            return .statement(delegate.statement)
        case "FlexStatementResponse":
            return .serviceResponse(delegate.serviceResponse)
        default:
            throw FlexError.badResponse
        }
    }

    // MARK: - State

    private var rootElement: String?
    private var statement = ParsedStatement(accountID: nil, baseCurrency: "CHF")
    private var statementSeen = false
    private var serviceResponse = FlexServiceResponse()
    private var textElement: String?
    private var textBuffer = ""

    private static let serviceTextElements: Set<String> = [
        "Status", "ErrorCode", "ErrorMessage", "ReferenceCode", "Url",
    ]

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String]
    ) {
        if rootElement == nil {
            rootElement = elementName
        }

        // Service response: capture the text content of the few known elements.
        if rootElement == "FlexStatementResponse", Self.serviceTextElements.contains(elementName) {
            textElement = elementName
            textBuffer = ""
            return
        }

        guard rootElement == "FlexQueryResponse" else { return }
        let attr = { (name: String) -> String? in
            guard let value = attributeDict[name], !value.isEmpty else { return nil }
            return value
        }

        switch elementName {
        case "FlexStatement":
            // A single-user query yields one statement; keep the first.
            guard !statementSeen else { return }
            statementSeen = true
            statement.accountID = attr("accountId")
            statement.fromDate = FlexValue.date(attr("fromDate"))
            statement.toDate = FlexValue.date(attr("toDate"))
            statement.whenGenerated = FlexValue.date(attr("whenGenerated"))

        case "AccountInformation":
            if let currency = attr("currency") {
                statement.baseCurrency = currency
            }

        case "OpenPosition":
            guard let symbol = attr("symbol"),
                  let position = FlexValue.decimal(attr("position")) else { return }
            statement.positions.append(ParsedPosition(
                symbol: symbol,
                description: attr("description") ?? symbol,
                isin: attr("isin"),
                assetCategory: attr("assetCategory") ?? "STK",
                currency: attr("currency") ?? statement.baseCurrency,
                fxRateToBase: FlexValue.decimal(attr("fxRateToBase")) ?? 1,
                position: position,
                markPrice: FlexValue.decimal(attr("markPrice")) ?? 0,
                positionValue: FlexValue.decimal(attr("positionValue")) ?? 0,
                costBasisMoney: FlexValue.decimal(attr("costBasisMoney")) ?? 0,
                fifoPnlUnrealized: FlexValue.decimal(attr("fifoPnlUnrealized")) ?? 0
            ))

        case "CashTransaction":
            guard let date = FlexValue.date(attr("dateTime") ?? attr("reportDate")),
                  let amount = FlexValue.decimal(attr("amount")),
                  let type = attr("type") else { return }
            statement.cashTransactions.append(ParsedCashTransaction(
                transactionID: attr("transactionID"),
                symbol: attr("symbol"),
                currency: attr("currency") ?? statement.baseCurrency,
                fxRateToBase: FlexValue.decimal(attr("fxRateToBase")) ?? 1,
                date: date,
                amount: amount,
                type: type,
                description: attr("description") ?? ""
            ))

        case "ChangeInDividendAccrual":
            guard let symbol = attr("symbol"),
                  let exDate = FlexValue.date(attr("exDate")) else { return }
            let code = attr("code") ?? "Po"
            statement.accruals.append(ParsedAccrual(
                symbol: symbol,
                currency: attr("currency") ?? statement.baseCurrency,
                fxRateToBase: FlexValue.decimal(attr("fxRateToBase")) ?? 1,
                exDate: exDate,
                payDate: FlexValue.date(attr("payDate")),
                quantity: FlexValue.decimal(attr("quantity")) ?? 0,
                grossAmount: FlexValue.decimal(attr("grossAmount")) ?? 0,
                netAmount: FlexValue.decimal(attr("netAmount")) ?? 0,
                isReversal: code.contains("Re")
            ))

        case "EquitySummaryByReportDateInBase":
            guard let reportDate = FlexValue.date(attr("reportDate")),
                  let total = FlexValue.decimal(attr("total")) else { return }
            statement.navPoints.append(ParsedNavPoint(
                reportDate: reportDate,
                cash: FlexValue.decimal(attr("cash")) ?? 0,
                stock: FlexValue.decimal(attr("stock")) ?? 0,
                total: total
            ))

        default:
            break // Unknown elements are ignored silently.
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard textElement != nil else { return }
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard elementName == textElement else { return }
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "Status": serviceResponse.status = text
        case "ErrorCode": serviceResponse.errorCode = Int(text)
        case "ErrorMessage": serviceResponse.errorMessage = text
        case "ReferenceCode": serviceResponse.referenceCode = text
        case "Url": serviceResponse.url = text
        default: break
        }
        textElement = nil
        textBuffer = ""
    }
}
