import Foundation
import SwiftSparql
import BrightFutures

final class PrismDB {
    let endpoint: URL

    init(endpoint: URL = URL(string: "https://prismdb.takanakahiko.me/sparql")!) {
        self.endpoint = endpoint
    }

    func episodes() -> Future<[Episode], QueryError> {
        let q = SelectQuery(
            where: WhereClause(
                patterns: subject(Var("iri")).rdfTypeIsPrismEpisode()
                    .prism話数(is: Var("number"))
                    .rdfsLabel(is: Var("label"))
                    .prismサブタイトル(is: Var("subtitle"))
                    .prismあにてれ(is: Var("anitv"))
                    .triples),
            order: [.asc(v: Var("number"))])
        return Request(endpoint: endpoint, select: q).fetch()
    }

    func lives() -> Future<[Live], QueryError> {
        let q = SelectQuery(
            capture: .expressions([
                (Var("iri"), .init(.sample(distinct: false, expression: .init(.var(Var("iri")))))),
                (Var("episodeIRI"), .init(.sample(distinct: false, expression: .init(.var(Var("episodeIRI")))))),
                (Var("song"), .init(.sample(distinct: false, expression: .init(.var(Var("song")))))),
                (Var("performer"), Expression(.groupConcat(distinct: false, expression: .init(.var(Var("performer"))), separator: " & "))),
                (Var("start"), .init(.sample(distinct: false, expression: .init(.var(Var("start")))))),
                (Var("end"), .init(.sample(distinct: false, expression: .init(.var(Var("end")))))),
            ]),
            where: WhereClause(
                patterns: subject(Var("iri")).rdfTypeIsPrismLive()
                    .prismLiveOfEpisode(is: Var("episodeIRI"))
                    .prismSongPerformed(is: Var("songIRI"))
                    .prismPerformer(is: Var("performerIRI"))
                    .optional {$0.prismStart(is: Var("start"))}
                    .optional {$0.prismEnd(is: Var("end"))}
                    .triples
                    + subject(Var("episodeIRI")).rdfTypeIsPrismEpisode()
                        .prism話数(is: Var("number")).triples
                    + subject(Var("songIRI")).rdfTypeIsPrismSong()
                        .prismName(is: Var("song")).triples
                    + subject(Var("performerIRI"))
                        .prismName(is: Var("performer")).triples),
            group: [.var(Var("iri")), .var(Var("number")), .var(Var("start"))],
            order: [.by(Var("number")), .by(Var("start"))])
        return Request(endpoint: endpoint, select: q).fetch()
    }

    struct Episode: Codable, Equatable, Hashable {
        var iri: String
        var label: String
        var subtitle: String
        var anitv: String
        var anitvURL: URL? {URL(string: anitv)}
    }

    struct Live: Codable, Equatable, Hashable {
        var iri: String
        var episodeIRI: String
        var song: String
        var performer: String
        var start: Double?
        var end: Double?
    }
}

extension TripleBuilder {
    func rdfsLabel(is v: GraphTerm) -> TripleBuilder<State> {
        return .init(base: self, appendingVerb: .init(IRIRef(value: "http://www.w3.org/2000/01/rdf-schema#label")), value: [.varOrTerm(.term(v))])
    }

    func rdfsLabel(is v: Var) -> TripleBuilder<State> {
        return .init(base: self, appendingVerb: .init(IRIRef(value: "http://www.w3.org/2000/01/rdf-schema#label")), value: [.var(v)])
    }
}

extension TripleBuilder {
    func prismName(is v: GraphTerm) -> TripleBuilder<State> {
        return .init(base: self, appendingVerb: .init(IRIRef(value: "http://www.w3.org/2000/01/rdf-schema#label")), value: [.varOrTerm(.term(v))])
    }

    func prismName(is v: Var) -> TripleBuilder<State> {
        return .init(base: self, appendingVerb: .init(IRIRef(value: "http://www.w3.org/2000/01/rdf-schema#label")), value: [.var(v)])
    }
}

extension TripleBuilder where State: TripleBuilderStateRDFTypeBoundType {
    func erasingSubjectType(_ block: @escaping (TripleBuilder<State>) -> (Var) -> TripleBuilder<State>) -> ((Var) -> TripleBuilder<TripleBuilderStateIncompleteSubject>) {
        return {v in .init(subject: self.subject, triples: block(self)(v).triples)}
    }
}
