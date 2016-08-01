require 'spec_helper'

describe Locking_Resource::Helper do
  describe '#process_start_time' do
    let(:dummy_class) do
      include Locking_Resource::Helper
    end

    # create an arbitrary list of plausible PIDs one per line
    pids = (1..rand(5)).map{rand(2**15)}
    pgrep_output = pids.join("\n") + "\n"
    early_ps_output = "Tue Jul 12 14:38:34 2016"
    late_ps_output = "Sat Jul 30 18:48:45 2016"
    command_string = "my command"

    context 'process exists' do
      let(:pgrep_output) { pgrep_output }
      let(:shellout) do

        def return_stdout(ard)
          # return a list of PIDs for pgrep(1)
          return pgrep_output if arg == "pgrep -f \"#{command_string}\""
          # We must return a known date somewhere so pick a PID to be that
          # and return that early date
          early_idx = rand(pids.length)
          return early_ps_output if arg.starts_with?('ps') and \
                                    arg.ends_with(pids[early_idx])
          # return our late date for all other PIDs
          return late_ps_output
        end

        double.stub(:command) do |arg|
          { run_command: nil,
            error: false,
            exitstatus: 0,
            stdout: return_stdout(arg),
            stderr: '',
              live_stream: '' }
        end
      end
      
      it 'returns the earliest time' do
        expect(dummy_class.new.process_start_time(command_string)).to
          eq(Time.parse(early_ps_output))
      end
    end
  end
end
