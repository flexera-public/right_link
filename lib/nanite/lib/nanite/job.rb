module Nanite
  class JobWarden
    attr_reader :serializer, :jobs

    def initialize(serializer)
      @serializer = serializer
      @jobs = {}
    end

    def new_job(request, targets, blk = nil)
      job = Job.new(request, targets, blk)
      jobs[job.token] = job
      job
    end

    def process(msg)
      if job = jobs[msg.token]
        job.process(msg)

        if job.completed?
          jobs.delete(job.token)
          if job.completed
            case job.completed.arity
            when 1
              job.completed.call(job.results)
            when 2
              job.completed.call(job.results, job)
            end
          end
        end
      end
    end
  end # JobWarden

  class Job
    attr_reader :results, :request, :token, :completed
    attr_accessor :targets # This can be updated when a request gets picked up from the offline queue

    def initialize(request, targets, blk = nil)
      @request = request
      @targets = targets
      @token = @request.token
      @results = {}
      @completed = blk
    end

    def process(msg)
      case msg
      when Result
        results[msg.from] = msg.results
        targets.delete(msg.from)
      end
    end

    def completed?
      targets.empty?
    end
  end # Job

end # Nanite
