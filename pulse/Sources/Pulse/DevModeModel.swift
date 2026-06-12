import Foundation
import Observation
import PulseKit

@Observable
@MainActor
final class DevModeModel {
    var smcDump: [String: String] = [:]
    var sysctls: [SysctlProperty] = []
    var processFDs: [ProcessFDSample] = []
    var isSampling = false
    
    private let sampler = DevModeSampler()
    
    func sample() async {
        isSampling = true
        defer { isSampling = false }
        
        async let smc = sampler.sampleSMC()
        async let sys = sampler.sampleSysctls()
        async let proc = sampler.sampleProcessFDs()
        
        let results = await (smc: smc, sys: sys, proc: proc)
        
        self.smcDump = results.smc
        self.sysctls = results.sys
        self.processFDs = results.proc
    }
}
