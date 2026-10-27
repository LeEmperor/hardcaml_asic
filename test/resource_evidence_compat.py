"""Intentional PT.5 deltas to the retired pre-PT.5 differential oracle.

Resource reconciliation itself is asserted by check_resource_evidence.py. These
helpers keep the old broad metric/format corpus comparing its original scope.
"""
DEFINITIONS = {
    'mapped_area': 'producer mapped library-known cell area; macro inclusion requires resource_evidence area cross-check',
    'mapped_cells': 'total mapped cell instance count, including macros',
    'final_utilization': 'producer standard-cell utilization; denominator/excluded regions not retained, not whole-design occupancy',
}


def collection_expected(payload):
    for key, definition in DEFINITIONS.items():
        payload['metrics'][key]['definition'] = definition
    payload['resource_evidence'] = None
    payload['resource_evidence_unavailable_reason'] = 'historical manifest resource inventory unavailable; retention not evaluated'
    return payload


def historical_human(text):
    return text.replace('  resource realization unavailable (historical results have no resource evidence)\n', '')
