# frozen_string_literal: true

require "spec_helper"

RSpec.describe AsyncHttpPool::TimeHelper do
  describe "#monotonic_time" do
    it "returns a numeric value" do
      time = described_class.monotonic_time
      expect(time).to be_a(Numeric)
    end

    it "returns increasing values on subsequent calls" do
      time1 = described_class.monotonic_time
      sleep(0.001) # Small delay
      time2 = described_class.monotonic_time

      expect(time2).to be > time1
    end

    it "measures elapsed time accurately" do
      start_time = described_class.monotonic_time
      sleep(0.05)
      end_time = described_class.monotonic_time
      elapsed = end_time - start_time

      # Should be approximately 0.05 seconds, allow some tolerance
      expect(elapsed).to be_between(0.04, 0.1)
    end

    it "is not affected by system clock changes" do
      # Monotonic time should continue increasing regardless of wall clock
      time1 = described_class.monotonic_time

      # Even if we stub Time.now to go backwards, monotonic time should increase
      allow(Time).to receive(:now).and_return(Time.now - 3600)

      sleep(0.001)
      time2 = described_class.monotonic_time

      expect(time2).to be > time1
    end
  end

  describe "#wall_clock_time" do
    it "converts monotonic timestamp to wall clock Time object" do
      monotonic_timestamp = described_class.monotonic_time
      wall_clock = described_class.wall_clock_time(monotonic_timestamp)

      expect(wall_clock).to be_a(Time)
    end

    it "returns approximately current time for recent monotonic timestamp" do
      monotonic_timestamp = described_class.monotonic_time
      wall_clock = described_class.wall_clock_time(monotonic_timestamp)

      # Should be very close to Time.now (within 1 second)
      expect((Time.now - wall_clock).abs).to be < 1.0
    end

    it "converts past monotonic timestamps to past wall clock times" do
      # Record a monotonic timestamp
      monotonic_timestamp = described_class.monotonic_time

      # Wait a bit
      sleep(0.1)

      # Convert to wall clock time
      wall_clock = described_class.wall_clock_time(monotonic_timestamp)

      # The wall clock time should be in the past (before now)
      expect(wall_clock).to be < Time.now

      # And approximately 0.1 seconds ago
      elapsed = Time.now - wall_clock
      expect(elapsed).to be_between(0.09, 0.2)
    end

    it "handles multiple conversions consistently" do
      # Create multiple monotonic timestamps
      monotonic1 = described_class.monotonic_time
      sleep(0.05)
      monotonic2 = described_class.monotonic_time
      sleep(0.05)
      monotonic3 = described_class.monotonic_time

      # Convert them all to wall clock time
      wall1 = described_class.wall_clock_time(monotonic1)
      wall2 = described_class.wall_clock_time(monotonic2)
      wall3 = described_class.wall_clock_time(monotonic3)

      # They should maintain the same ordering and approximate intervals
      expect(wall1).to be < wall2
      expect(wall2).to be < wall3

      # Intervals should be approximately 0.05 seconds
      interval1 = wall2 - wall1
      interval2 = wall3 - wall2

      expect(interval1).to be_between(0.04, 0.1)
      expect(interval2).to be_between(0.04, 0.1)
    end

    it "can be used as a module method" do
      # Test that TimeHelper can be used without including it
      monotonic = AsyncHttpPool::TimeHelper.monotonic_time
      wall_clock = AsyncHttpPool::TimeHelper.wall_clock_time(monotonic)

      expect(wall_clock).to be_a(Time)
    end
  end

  describe "when included in a class" do
    let(:test_class) do
      Class.new do
        include AsyncHttpPool::TimeHelper

        def capture_timing
          start = monotonic_time
          sleep(0.05)
          finish = monotonic_time
          {
            start: start,
            finish: finish,
            duration: finish - start,
            wall_start: wall_clock_time(start),
            wall_finish: wall_clock_time(finish)
          }
        end
      end
    end

    it "provides instance methods" do
      instance = test_class.new
      timing = instance.capture_timing

      expect(timing[:duration]).to be_between(0.04, 0.1)
      expect(timing[:wall_start]).to be_a(Time)
      expect(timing[:wall_finish]).to be_a(Time)
      expect(timing[:wall_finish]).to be > timing[:wall_start]
    end
  end

  describe "duration calculations" do
    it "accurately measures short durations" do
      start = described_class.monotonic_time
      sleep(0.01)
      finish = described_class.monotonic_time
      duration = finish - start

      expect(duration).to be_between(0.009, 0.05)
    end

    it "accurately measures longer durations" do
      start = described_class.monotonic_time
      sleep(0.2)
      finish = described_class.monotonic_time
      duration = finish - start

      expect(duration).to be_between(0.19, 0.3)
    end

    it "can measure very short durations" do
      start = described_class.monotonic_time
      # Do something very quick
      1000.times { |i| i * 2 }
      finish = described_class.monotonic_time
      duration = finish - start

      # Should be a very small but measurable duration
      expect(duration).to be >= 0
      expect(duration).to be < 0.1
    end
  end
end
